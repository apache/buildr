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

module Buildr #nodoc

  # A utility class that helps with colorizing output for interactive shells where appropriate
  class Console
    class << self
      def use_color
        @use_color.nil? ? false : @use_color
      end

      def use_color=(use_color)
        if Buildr::Util.win_os? && use_color
          begin
            require 'Win32/Console/ANSI'
          rescue LoadError
            return
          end
        end
        @use_color = use_color
      end

      # Emit message with color at the start of the message and the clear color command at the end of the sequence.
      def color(message, color)
        raise "Unknown color #{color.inspect}" unless [:green, :red, :blue].include?(color)
        return message unless use_color
        constants = {:green => "\e[32m", :red => "\e[31m", :blue => "\e[34m"}
        "#{constants[color]}#{message}\e[0m"
      end

      # Return the [rows, columns] of a console or nil if unknown
      def console_dimensions
        begin
          if Buildr::Util.win_os?
            Win32::Console.new(Win32::Console::STD_OUTPUT_HANDLE).MaxWindow
          elsif $stdout.isatty
            if /solaris/ =~ RUBY_PLATFORM and
              `stty` =~ /\brows = (\d+).*\bcolumns = (\d+)/
              [$2, $1].map { |c| x.to_i }
            else
              `stty size 2> /dev/null`.split.map { |x| x.to_i }.reverse
            end
          else
            nil
          end
        rescue => e
          nil
        end
      end

      # Return the number of columns in console or nil if unknown
      def output_cols
        d = console_dimensions
        d ? d[0] : nil
      end

      def agree?(message)
        agree(message)
      end

      def ask_password(prompt)
        ask(prompt) { |q| q.echo = '*' }
      end

      def present_menu(header, options)
        choose do |menu|
          menu.header = header
          options.each_pair do |message, result|
            menu.choice(message) { result }
          end
        end
      end
    end
  end
end

Buildr::Console.use_color = $stdout.isatty
