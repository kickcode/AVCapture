class AppDelegate
  BUTTON_SIZE = [90, 30]
  FPS = 30
  SAMPLE_RATE = 44100.0

  def applicationDidFinishLaunching(notification)
    buildMenu
    buildWindow

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
    self.set_button_frame
    @button.title = "Start"
    @button.target = self
    @button.action = 'toggle_capture:'
    @mainWindow.contentView.addSubview(@button)

    @image_button = NSButton.alloc.initWithFrame(CGRectZero)
    self.set_image_button_frame
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
    self.set_audio_level_frame
    @mainWindow.contentView.addSubview(@audio_level)

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
    self.set_button_frame
    self.set_image_button_frame
    self.set_audio_level_frame
    self.update_video_preview if @is_running
  end

  def set_button_frame
    @button.frame = [[0, 0], BUTTON_SIZE]
  end

  def set_image_button_frame
    @image_button.frame = [[@mainWindow.contentView.bounds.size.width - BUTTON_SIZE.first, 0], BUTTON_SIZE]
  end

  def set_audio_level_frame
    @audio_level.frame = [[BUTTON_SIZE.first, 0], [@mainWindow.contentView.bounds.size.width - (BUTTON_SIZE.first * 2), BUTTON_SIZE.last]]
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
          @video_input.appendSampleBuffer(buffer) if @video_input.isReadyForMoreMediaData && @asset_writer.status == AVAssetWriterStatusWriting
        elsif output.is_a?(AVCaptureAudioDataOutput)
          @audio_input.appendSampleBuffer(buffer) if @audio_input.isReadyForMoreMediaData && @asset_writer.status == AVAssetWriterStatusWriting
        end
      end
    end
  end
end
