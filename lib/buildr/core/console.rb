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
        begin
          if Buildr::Util.win_os? && use_color
            if Buildr::Util.java_platform?
              require 'java'
              require 'readline'
              begin
                # Attempt jruby 1.7.0->1.7.4 code path
                java_import 'jline.console.ConsoleReader'
                input = $stdin.to_inputstream
                output = $stdout.to_outputstream
                @java_console = Java::JlineConsole::ConsoleReader.new(input, output)
                @java_console.set_history_enabled(false)
                @java_console.set_bell_enabled(true)
                @java_console.set_pagination_enabled(false)
                @java_terminal = @java_console.getTerminal
              rescue Error
                # Attempt jruby 1.6.* code path

                java_import java.io.OutputStreamWriter
                java_import java.nio.channels.Channels
                java_import jline.ConsoleReader
                java_import jline.Terminal

                @java_input = Channels.newInputStream($stdin.to_channel)
                @java_output = OutputStreamWriter.new(Channels.newOutputStream($stdout.to_channel))
                @java_terminal = Terminal.getTerminal
                @java_console = ConsoleReader.new(@java_input, @java_output)
                @java_console.setUseHistory(false)
                @java_console.setBellEnabled(true)
                @java_console.setUsePagination(false)
              end
            else
              require 'Win32/Console/ANSI'
            end
          end
        rescue Java::JavaLang::IncompatibleClassChangeError
          # Unfortunately we have multiple incompatible jline libraries
          # in the classpath. This is probably because we are using jruby
          # 1.7.5 with a library like scala and both use incompatible jline
          # implementations
          return
        rescue NameError
          return
        rescue LoadError
          return
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
            if Buildr::Util.java_platform?
              if JRUBY_VERSION =~ /^1.7/
                [@java_terminal.get_width, @java_terminal.get_height]
              else
                [@java_terminal.getTerminalWidth, @java_terminal.getTerminalHeight]
              end
            else
              Win32::Console.new(Win32::Console::STD_OUTPUT_HANDLE).MaxWindow
            end
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
