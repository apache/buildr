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


gem 'jekyll', '~> 0.6.2' # skip past some buggy versions
require 'rake/tasklib'
require 'jekyll'


class JekyllTask < Rake::TaskLib
  def initialize(name=:jekyll)  # :yield: self
    @name = name
    @source = name
    @target = name
    yield self if block_given?
    task name, :auto, :needs=>[@source] do |task, args|
      generate args.auto
    end
    if @source != @target
      file @target=>FileList["#{@source}/**/*"] do
        generate
      end
      task 'clobber' do
        rm_rf @target
      end
    end
  end

  attr_accessor :source
  attr_accessor :target

  def generate(auto = false)
    options = { 'source'=>source, 'destination'=>target }
    options = Jekyll.configuration(options)
    site = Jekyll::Site.new(options)

    if auto
      require 'directory_watcher'
      puts "Auto generating: just edit a page and save, watch the console to see when we're done regenerating pages"
      dw = DirectoryWatcher.new(source)
      dw.interval = 1
      dw.glob = Dir.chdir(source) do
        dirs = Dir['*'].select { |x| File.directory?(x) }
        dirs -= [target]
        dirs = dirs.map { |x| "#{x}/**/*" }
        dirs += ['*']
      end
      dw.start
      dw.add_observer do |*args|
        t = Time.now.strftime("%Y-%m-%d %H:%M:%S")
        puts "[#{t}] regeneration: #{args.size} files changed"
        site.process
        puts "Done"
      end
      loop { sleep 1 }
    else
      puts "Generating documentation in #{target}"
      site.process
      touch target
    end
  end
end


module TocFilter
  def toc(input)
    input.scan(/<(h2)(?:>|\s+(.*?)>)([^<]*)<\/\1\s*>/mi).inject(%{<ol class="toc">}) { |toc, entry|
      id = entry[1][/^id=(['"])(.*)\1$/, 2]
      title = entry[2].gsub(/<(\w*).*?>(.*?)<\/\1\s*>/m, '\2').strip
      toc << %{<li><a href="##{id}">#{title}</a></li>}
    } << "</ol>"
  end
end
Liquid::Template.register_filter(TocFilter)



# Under Ruby 1.9 [a,b,c].to_s doesn't join the array first. (Jekyll 0.5.2 requires this)
module Jekyll
  class HighlightBlock < Liquid::Block
    def render(context)
      if context.registers[:site].pygments
        render_pygments(context, super.join)
      else
        render_codehighlighter(context, super.join)
      end
    end
  end
end

# Ruby 1.9 has sane closure scoping which manages to mess Liquid filters. (Liquid 2.0.0 requires this)
module Liquid
  class Variable
    def render(context)
      return '' if @name.nil?
      @filters.inject(context[@name]) do |output, filter|
        filterargs = filter[1].to_a.collect do |a|
         context[a]
        end
        begin
          context.invoke(filter[0], output, *filterargs)
        rescue FilterNotFound
          raise FilterNotFound, "Error - filter '#{filter[0]}' in '#{@markup.strip}' could not be found."
        end
      end
    end
  end
end
