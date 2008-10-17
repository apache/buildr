# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.


# Let's see if we can use Growl.  Must be running from console in verbose mode.
if $stdout.isatty && verbose
  notify = lambda do |type, title, message|
    begin
      # Loading Ruby Cocoa can slow the build down (hooks on Object class), so we're
      # saving the best for last and only requiring it at the very end.
      require 'osx/cocoa'
      icon = OSX::NSApplication.sharedApplication.applicationIconImage
      icon = OSX::NSImage.alloc.initWithContentsOfFile(File.join(File.dirname(__FILE__), '../resources/buildr.icns'))

      # Register with Growl, that way you can turn notifications on/off from system preferences.
      OSX::NSDistributedNotificationCenter.defaultCenter.
        postNotificationName_object_userInfo_deliverImmediately(:GrowlApplicationRegistrationNotification, nil,
          { :ApplicationName=>'Buildr', :AllNotifications=>['Completed', 'Failed'], 
            :ApplicationIcon=>icon.TIFFRepresentation }, true)

      OSX::NSDistributedNotificationCenter.defaultCenter.
        postNotificationName_object_userInfo_deliverImmediately(:GrowlNotification, nil,
          { :ApplicationName=>'Buildr', :NotificationName=>type,
            :NotificationTitle=>title, :NotificationDescription=>message }, true)
    rescue Exception
      # We get here in two cases: system doesn't have Growl installed so one of the OSX
      # calls raises an exception; system doesn't have osx/cocoa, e.g. MacPorts Ruby 1.9,
      # so we also need to rescue LoadError.
    end
  end  
  
  Buildr.application.on_completion { |title, message| notify['Completed', title, message] if verbose }
  Buildr.application.on_failure { |title, message, ex| notify['Failed', title, message] if verbose }
end
