class AppDelegate
  BUTTON_SIZE = [150, 30]

  def applicationDidFinishLaunching(notification)
    buildMenu
    buildWindow

    @session = AVCaptureSession.alloc.init
    @session.sessionPreset = AVCaptureSessionPresetHigh

    devices = AVCaptureDevice.devices
    video_device = devices.select { |device| device.hasMediaType(AVMediaTypeVideo) }.first
    audio_device = devices.select { |device| device.hasMediaType(AVMediaTypeAudio) }.first

    video_input = AVCaptureDeviceInput.deviceInputWithDevice(video_device, error: nil)
    audio_input = AVCaptureDeviceInput.deviceInputWithDevice(audio_device, error: nil)

    if @session.canAddInput(video_input) && @session.canAddInput(audio_input)
      @session.addInput(video_input)
      @session.addInput(audio_input)
    end

    @output = AVCaptureMovieFileOutput.alloc.init
    @session.addOutput(@output) if @session.canAddOutput(@output)

    @audio_output = AVCaptureAudioDataOutput.alloc.init
    @session.addOutput(@audio_output) if @session.canAddOutput(@audio_output)

    @button = NSButton.alloc.initWithFrame(CGRectZero)
    self.set_button_frame
    @button.title = "Start"
    @button.target = self
    @button.action = 'toggle_capture:'
    @mainWindow.contentView.addSubview(@button)

    NSNotificationCenter.defaultCenter.addObserver(self,
      selector: 'didStartRunning',
      name: AVCaptureSessionDidStartRunningNotification,
      object: nil)

    NSTimer.scheduledTimerWithTimeInterval(0.1, target: self, selector: 'checkAudioLevels', userInfo: nil, repeats: true)
  end

  def checkAudioLevels
    return unless @is_running
    sum = 0
    @audio_output.connections.first.audioChannels.each_with_index do |channel, index|
      NSLog "CHANNEL[#{index}]: avg: #{channel.averagePowerLevel}, peak: #{channel.peakHoldLevel}"
      sum += (channel.averagePowerLevel + channel.peakHoldLevel) / 2.0
    end
    avg = sum / @audio_output.connections.first.audioChannels.count
    NSLog "AVERAGE AVERAGE: #{avg}"
  end

  def windowDidResize(notification)
    self.set_button_frame
    self.update_video_preview if @is_running
  end

  def set_button_frame
    @button.frame = [[0, 0], BUTTON_SIZE]
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
      @output.stopRecording
      @button.title = "Stopping..."
    else
      @is_working = true
      @session.startRunning
      @button.title = "Starting..."
    end
    @button.enabled = false
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
    @output.startRecordingToOutputFileURL(url, recordingDelegate: self)
  end

  def captureOutput(output, didStartRecordingToOutputFileAtURL: url, fromConnections: connections)
    @button.title = "Stop"
    @button.enabled = true
    @is_working = false
    @is_running = true
  end

  def captureOutput(output, didFinishRecordingToOutputFileAtURL: url, fromConnections: connections, error: err)
    @session.stopRunning
    @button.title = "Start"
    @button.enabled = true
    @is_working = false
    @is_running = false
  end
end