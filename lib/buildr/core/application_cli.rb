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

# Portion of this file derived from Rake.
# Copyright (c) 2003, 2004 Jim Weirich
#
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


require 'getoptlong'


module Buildr
  module CommandLineInterface
    
    OPTIONS = [     # :nodoc:
        ['--help',     '-h', GetoptLong::NO_ARGUMENT,
          'Display this help message.'],
        ['--nosearch', '-n', GetoptLong::NO_ARGUMENT,
          'Do not search parent directories for the buildfile.'],
        ['--quiet',    '-q', GetoptLong::NO_ARGUMENT,
          'Do not log messages to standard output.'],
        ['--buildfile', '-f', GetoptLong::REQUIRED_ARGUMENT,
          'Use FILE as the buildfile.'],
        ['--require',  '-r', GetoptLong::REQUIRED_ARGUMENT,
          'Require MODULE before executing buildfile.'],
        ['--trace',    '-t', GetoptLong::NO_ARGUMENT,
          'Turn on invoke/execute tracing, enable full backtrace.'],
        ['--prereqs',  '-P', GetoptLong::OPTIONAL_ARGUMENT,
          'Display tasks and dependencies, then exit.'],
        ['--version',  '-v', GetoptLong::NO_ARGUMENT,
          'Display the program version.'],
        ['--environment', '-e', GetoptLong::REQUIRED_ARGUMENT,
          'Environment name (e.g. development, test, production).']
      ]

    def collect_tasks
      top_level_tasks.clear
      ARGV.each do |arg|
        if arg =~ /^(\w+)=(.*)$/
          ENV[$1.upcase] = $2
        else
          top_level_tasks << arg
        end
      end
      top_level_tasks.push("default") if top_level_tasks.size == 0
    end
    
    def parse_options
      opts = GetoptLong.new(*command_line_options)
      opts.each { |opt, value| do_option(opt, value) }
    end

    def do_option(opt, value)
      case opt
      when '--help'
        help
        exit
      when '--buildfile'
        rakefiles.clear
        rakefiles << value
      when '--version'
        puts version
        exit
      when '--environment'
        ENV['BUILDR_ENV'] = value
      when '--require'
        requires << value
      when '--prereqs'
        options.show_prereqs = true
        options.show_task_pattern = Regexp.new(value || '.')
      when '--nosearch', '--quiet', '--trace'
        super
      end
    end

    def command_line_options
      OPTIONS.collect { |lst| lst[0..-2] }
    end

    def version
      "Buildr #{Buildr::VERSION} #{RUBY_PLATFORM[/java/] && '(JRuby '+JRUBY_VERSION+')'}"
    end

    def usage
      puts version
      puts
      puts 'Usage:'
      puts '  buildr [options] [tasks] [name=value]'
    end
    
    def help
      usage
      puts
      puts 'Options:'
      OPTIONS.sort.each do |long, short, mode, desc|
        if mode == GetoptLong::REQUIRED_ARGUMENT
          if desc =~ /\b([A-Z]{2,})\b/
            long = long + "=#{$1}"
          end
        end
        printf "  %-20s (%s)\n", long, short
        printf "      %s\n", desc
      end
      puts
      puts 'For help with your buildfile:'
      puts '  buildr help'
    end
   
  end
end
