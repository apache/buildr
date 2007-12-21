require "core/common"
require "core/project"


task "help" do
  # Greeater.
  Rake.application.usage
  puts

  # Show only the top-level projects.
  projects.reject(&:parent).tap do |top_level|
    unless top_level.empty?
      puts "Top-level projects (buildr help:projects for full list):"
      width = [top_level.map(&:name).map(&:size), 20].flatten.max
      top_level.each do |project|
        puts project.comment.blank? ? project.name : ("  %-#{width}s  # %s" % [project.name, project.comment])
      end
      puts
    end
  end

  # Show all the top-level tasks, excluding projects.
  puts "Common tasks:"
  task("help:tasks").invoke
  puts
  puts "For help on command line options:"
  puts "  buildr --help"
end


module Buildr

  # :call-seq:
  #   help() { ... }
  #
  # Use this to enhance the help task, e.g. to print some important information about your build,
  # configuration options, build instructions, etc.
  def help(&block)
    Rake.application["help"].enhance &block
  end

end


namespace "help" do

  desc "List all projects defined by this buildfile"
  task "projects" do
    width = projects.map(&:name).map(&:size).max
    projects.each do |project|
      puts project.comment.blank? ? "  #{project.name}" : ("  %-#{width}s  # %s" % [project.name, project.comment])
    end
  end

  desc "List all tasks available from this buildfile"
  task "tasks" do
    Rake.application.tasks.select(&:comment).reject { |task| Project === task }.tap do |tasks|
      width = [tasks.map(&:name).map(&:size), 20].flatten.max
      tasks.each do |task|
        printf "  %-#{width}s  # %s\n", task.name, task.comment
      end
      puts
    end
  end

end
