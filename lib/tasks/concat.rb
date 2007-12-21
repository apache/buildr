module Buildr

  # A file task that concatenates all its prerequisites to create a new file.
  #
  # For example:
  #   concat("master.sql"=>["users.sql", "orders.sql", reports.sql"]
  #
  # See also Buildr#concat.
  class ConcatTask < Rake::FileTask
    def initialize(*args) #:nodoc:
      super
      enhance do |task|
        content = prerequisites.inject("") do |content, prereq|
          content << File.read(prereq.to_s) if File.exists?(prereq) && !File.directory?(prereq)
          content
        end
        File.open(task.name, "wb") { |file| file.write content }
      end
    end
  end

  # :call-seq:
  #    concat(target=>files) => task
  #
  # Creates and returns a file task that concatenates all its prerequisites to create
  # a new file. See #ConcatTask.
  #
  # For example:
  #   concat("master.sql"=>["users.sql", "orders.sql", reports.sql"]
  def concat(args)
    file, arg_names, deps = Rake.application.resolve_args([args])
    ConcatTask.define_task(File.expand_path(file)=>deps)
  end

end
