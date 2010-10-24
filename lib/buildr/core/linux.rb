# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with this
# work for additional information regarding copyright ownership.  The ASF
# licenses this file to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
# License for the specific language governing permissions and limitations under
# the License.


# Let's see if we can use notify-send.  Must be running from console in verbose mode.
if $stdout.isatty && verbose

  def command_exist?(command)
    system("which #{command} > /dev/null 2>/dev/null")
    $?.exitstatus == 0
  end

  def notify_send(type, title, message)
    icon = File.join(File.dirname(__FILE__), '../resources/', type.to_s + '.png')
    system "notify-send -i #{icon} \"#{title}\" \"#{message}\""
  end

  if command_exist? 'notify-send'
    Buildr.application.on_completion { |title, message| notify_send(:completed, title, message) if verbose }
    Buildr.application.on_failure { |title, message, ex| notify_send(:failed, title, message) if verbose }
  end

end


