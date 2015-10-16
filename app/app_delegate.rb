class AppDelegate
  BUTTON_SIZE = [90, 30]
  FPS = 30
  SAMPLE_RATE = 44100.0

  def applicationDidFinishLaunching(notification)
    buildMenu
    buildWindow

    @speed = 1.0

    @session = AVCaptureSession.alloc.init
    @session.sessionPreset = AVCaptureSessionPreset1280x720

    devices = AVCaptureDevice.devices
    video_device = devices.select { |device| device.hasMediaType(AVMediaTypeVideo) }.first
    video_device.lockForConfiguration(nil)
    video_device.setActiveVideoMinFrameDuration(CMTimeMake(1, FPS))
    video_device.setActiveVideoMaxFrameDuration(CMTimeMake(1, FPS))
    video_device.unlockForConfiguration
    audio_device = devices.select { |device| device.hasMediaType(AVMediaTypeAudio) }.first

    video_input = AVCaptureDeviceInput.deviceInputWithDevice(video_device, error: nil)
    audio_input = AVCaptureDeviceInput.deviceInputWithDevice(audio_device, error: nil)

    if @session.canAddInput(video_input) && @session.canAddInput(audio_input)
      @session.addInput(video_input)
      @session.addInput(audio_input)
    end

    @video_queue = Dispatch::Queue.new("com.kickcode.avcapture.video_processor")
    @video_output = AVCaptureVideoDataOutput.alloc.init
    @video_output.setSampleBufferDelegate(self, queue: @video_queue.dispatch_object)
    @session.addOutput(@video_output) if @session.canAddOutput(@video_output)

    @audio_queue = Dispatch::Queue.new("com.kickcode.avcapture.audio_processor")
    @audio_output = AVCaptureAudioDataOutput.alloc.init
    @audio_output.setSampleBufferDelegate(self, queue: @audio_queue.dispatch_object)
    @session.addOutput(@audio_output) if @session.canAddOutput(@audio_output)

    @image_output = AVCaptureStillImageOutput.alloc.init
    @session.addOutput(@image_output) if @session.canAddOutput(@image_output)

    @button = NSButton.alloc.initWithFrame(CGRectZero)
    @button.title = "Start"
    @button.target = self
    @button.action = 'toggle_capture:'
    @mainWindow.contentView.addSubview(@button)

    @speed_label = NSTextField.alloc.initWithFrame(CGRectZero)
    @speed_label.bezeled = false
    @speed_label.drawsBackground = false
    @speed_label.stringValue = "#{@speed}x"
    @mainWindow.contentView.addSubview(@speed_label)

    @speed_slider = NSSlider.alloc.initWithFrame(CGRectZero)
    @speed_slider.minValue = 1
    @speed_slider.maxValue = 20
    @speed_slider.integerValue = (@speed / 0.5)
    @speed_slider.target = self
    @speed_slider.action = 'speed_changed:'
    @mainWindow.contentView.addSubview(@speed_slider)

    @image_button = NSButton.alloc.initWithFrame(CGRectZero)
    @image_button.title = "Snap"
    @image_button.target = self
    @image_button.action = 'snap_picture:'
    @mainWindow.contentView.addSubview(@image_button)

    @audio_level = Motion::Meter::ThresholdMeter.alloc.initWithFrame(CGRectZero)
    @audio_level.add_threshold(-20, -5, NSColor.greenColor)
    @audio_level.add_threshold(-5, 3, NSColor.yellowColor)
    @audio_level.add_threshold(3, 10, NSColor.redColor)
    @audio_level.min_value = -20
    @audio_level.max_value = 10
    @mainWindow.contentView.addSubview(@audio_level)

    self.set_ui_frames

    NSNotificationCenter.defaultCenter.addObserver(self,
      selector: 'didStartRunning',
      name: AVCaptureSessionDidStartRunningNotification,
      object: nil)

    NSNotificationCenter.defaultCenter.addObserver(self,
      selector: 'didStopRunning',
      name: AVCaptureSessionDidStopRunningNotification,
      object: nil)

    NSTimer.scheduledTimerWithTimeInterval(0.1, target: self, selector: 'checkAudioLevels', userInfo: nil, repeats: true)
  end

  def checkAudioLevels
    return unless @is_running
    sum = 0
    @audio_output.connections.first.audioChannels.each_with_index do |channel, index|
      sum += (channel.averagePowerLevel + channel.peakHoldLevel) / 2.0
    end
    avg = sum / @audio_output.connections.first.audioChannels.count
    @audio_level.value = avg
  end

  def windowDidResize(notification)
    self.set_ui_frames
    self.update_video_preview if @is_running
  end

  def set_ui_frames
    @button.frame = [[0, 0], BUTTON_SIZE]
    @speed_label.frame = [[BUTTON_SIZE.first, 5], [35, 20]]
    @speed_slider.frame = [[@speed_label.frame.origin.x + @speed_label.frame.size.width, 0], [100, 30]]
    @image_button.frame = [[@mainWindow.contentView.bounds.size.width - BUTTON_SIZE.first, 0], BUTTON_SIZE]
    @audio_level.frame = [[@speed_slider.frame.origin.x + @speed_slider.frame.size.width, 0], [@mainWindow.contentView.bounds.size.width - (@button.frame.size.width + @speed_label.frame.size.width + @speed_slider.frame.size.width + @image_button.frame.size.width), BUTTON_SIZE.last]]
  end

  def update_video_preview
    if @view
      @video_preview.removeFromSuperlayer if @video_preview
      @view.removeFromSuperview
    end

    bounds = @mainWindow.contentView.bounds
    bounds.size.height -= BUTTON_SIZE.last
    bounds.origin.y += BUTTON_SIZE.last
    @view = NSView.alloc.initWithFrame(bounds)
    layer = CALayer.layer
    @view.setLayer(layer)
    @view.setWantsLayer(true)
    @mainWindow.contentView.addSubview(@view)

    @video_preview.frame = @view.bounds
    @view.layer.addSublayer(@video_preview)
  end

  def toggle_capture(sender)
    return if @is_working
    @is_running ||= false
    if @is_running
      @is_working = true
      @session.stopRunning
      @button.title = "Stopping..."
    else
      @is_working = true
      @session.startRunning
      @button.title = "Starting..."
    end
    @button.enabled = false
  end

  def speed_changed(sender)
    @speed = sender.integerValue * 0.5
    @speed_label.stringValue = "#{@speed}x"
  end

  def snap_picture(sender)
    return unless @is_running

    image_connection = nil
    @image_output.connections.each do |connection|
      connection.inputPorts.each do |port|
        image_connection = connection if port.mediaType == AVMediaTypeVideo
      end
    end

    return if image_connection.nil?

    @image_output.captureStillImageAsynchronouslyFromConnection(image_connection, completionHandler: Proc.new do |sample_buffer, error|
      AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sample_buffer).writeToFile("/Users/#{NSUserName()}/Desktop/temp#{Time.now.to_i}.jpg", atomically: false) if error.nil?
    end)
  end

  def buildWindow
    @mainWindow = NSWindow.alloc.initWithContentRect([[240, 180], [480, 360]],
      styleMask: NSTitledWindowMask|NSClosableWindowMask|NSMiniaturizableWindowMask|NSResizableWindowMask,
      backing: NSBackingStoreBuffered,
      defer: false)
    @mainWindow.title = NSBundle.mainBundle.infoDictionary['CFBundleName']
    @mainWindow.orderFrontRegardless
    @mainWindow.delegate = self
  end

  def didStartRunning
    @video_preview ||= AVCaptureVideoPreviewLayer.alloc.initWithSession(@session)
    self.update_video_preview

    url = NSURL.alloc.initWithString("file:///Users/#{NSUserName()}/Desktop/temp#{Time.now.to_i}.mp4")
    @asset_writer = AVAssetWriter.assetWriterWithURL(url, fileType: AVFileTypeMPEG4, error: nil)
    video_settings = {
      AVVideoCodecKey => AVVideoCodecH264,
      AVVideoWidthKey => 1280,
      AVVideoHeightKey => 720
    }
    @video_input = AVAssetWriterInput.alloc.initWithMediaType(AVMediaTypeVideo, outputSettings: video_settings)
    @video_input.expectsMediaDataInRealTime = true
    audio_settings = {
      AVFormatIDKey => KAudioFormatMPEG4AAC,
      AVNumberOfChannelsKey => 2,
      AVSampleRateKey => SAMPLE_RATE,
      AVEncoderBitRateKey => KAudioStreamAnyRate
    }
    @audio_input = AVAssetWriterInput.alloc.initWithMediaType(AVMediaTypeAudio, outputSettings: audio_settings)
    @audio_input.expectsMediaDataInRealTime = true
    @asset_writer.addInput(@video_input) if @asset_writer.canAddInput(@video_input)
    @asset_writer.addInput(@audio_input) if @asset_writer.canAddInput(@audio_input)

    @button.title = "Stop"
    @button.enabled = true
    @is_working = false
  end

  def didStopRunning
    @asset_writer.finishWritingWithCompletionHandler(Proc.new do
      case @asset_writer.status
      when AVAssetWriterStatusFailed
        NSLog "ASSET WRITER ERROR: #{@asset_writer.error.localizedDescription}"
      when AVAssetWriterStatusCompleted
        NSLog "ASSET WRITER SUCCESS"
      else
        NSLog "ASSET WRITER: #{@asset_writer.status}"
      end
      @button.title = "Start"
      @button.enabled = true
      @is_working = false
      @is_running = false
      @playhead = nil
    end)
  end

  def captureOutput(output, didOutputSampleBuffer: buffer, fromConnection: connection)
    return unless CMSampleBufferDataIsReady(buffer)
    return if @asset_writer.nil? || @video_input.nil? || @audio_input.nil?
    if @asset_writer.status != AVAssetWriterStatusCompleted
      if @asset_writer.status < AVAssetWriterStatusWriting
        @asset_writer.startWriting
        @asset_writer.startSessionAtSourceTime(CMSampleBufferGetPresentationTimeStamp(buffer))
        @is_running = true
      end

      if @is_running && @asset_writer.status == AVAssetWriterStatusWriting
        if output.is_a?(AVCaptureVideoDataOutput)
          self.modify_video_buffer(buffer)
        elsif output.is_a?(AVCaptureAudioDataOutput)
          @audio_input.appendSampleBuffer(buffer) if @speed == 1.0 && @audio_input.isReadyForMoreMediaData && @asset_writer.status == AVAssetWriterStatusWriting
        end
      end
    end
  end

  def modify_video_buffer(buffer)
    @playhead ||= CMSampleBufferGetPresentationTimeStamp(buffer)

    timing_info = KCMTimingInfoInvalid
    timing_info.presentationTimeStamp = @playhead
    timing_info.duration = CMSampleBufferGetDuration(buffer)
    timing_info.duration.value /= @speed
    @playhead.value += timing_info.duration.value

    timing_info.decodeTimeStamp = KCMTimeInvalid
    timing_info_ptr = Pointer.new('{_CMSampleTimingInfo={_CMTime=qiIq}{_CMTime=qiIq}{_CMTime=qiIq}}')
    timing_info_ptr[0] = timing_info

    updated_buffer_ptr = Pointer.new(:object)
    CMSampleBufferCreateCopyWithNewTiming(KCFAllocatorDefault, buffer, 1, timing_info_ptr, updated_buffer_ptr)
    updated_buffer = updated_buffer_ptr[0]

    @video_input.appendSampleBuffer(updated_buffer) if @video_input.isReadyForMoreMediaData && @asset_writer.status == AVAssetWriterStatusWriting
  end
end
