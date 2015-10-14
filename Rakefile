# -*- coding: utf-8 -*-
$:.unshift("/Library/RubyMotion/lib")
require 'motion/project/template/osx'

begin
  require 'bundler'
  Bundler.require
rescue LoadError
end

Motion::Project::App.setup do |app|
  # Use `rake config' to see complete project settings.
  app.name = 'AVCapture'

  app.frameworks += ['AVFoundation']

  app.sdk_version = '10.10'
  app.deployment_target = '10.10'
end
