class AppDelegate
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
  end

  def windowDidResize(notification)
    self.set_button_frame
  end

  def set_button_frame
    size = @mainWindow.frame.size
    button_size = [150, 30]
    @button.frame = [[(size.width / 2.0) - (button_size[0] / 2.0), (size.height / 2.0) - (button_size[1] / 2.0)], button_size]
  end

  def toggle_capture(sender)
    @is_running ||= false
    if @is_running
      @session.stopRunning
      @button.title = "Start"
    else
      @session.startRunning
      @button.title = "Stop"
    end
    @is_running = !@is_running
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
    url = NSURL.alloc.initWithString("file:///Users/#{NSUserName()}/Desktop/temp#{Time.now.to_i}.mp4")
    @output.startRecordingToOutputFileURL(url, recordingDelegate: self)
  end
end