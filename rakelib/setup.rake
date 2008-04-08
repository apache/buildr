# True if running on the Windows operating sytem.  Different from Gem.win_platform?
# which returns true if running on the Windows platform of MRI, false when using JRuby.
def windows?
  Config::CONFIG['host_os'] =~ /windows|cygwin|bccwin|cygwin|djgpp|mingw|mswin|wince/i
end


# Finds and returns path to executable.  Consults PATH environment variable.
# Returns nil if executable not found.
def which(name)
  if windows?
    path = ENV['PATH'].split(File::PATH_SEPARATOR).map { |path| path.gsub('\\', '/') }.map { |path| "#{path}/#{name}.{exe,bat,com}" }
  else
    path = ENV['PATH'].split(File::PATH_SEPARATOR).map { |path| "#{path}/#{name}" }
  end
  FileList[path].existing.first
end


def install_gem(name, ver_requirement = nil)
  dep = Gem::Dependency.new(name, ver_requirement)
  if Gem::SourceIndex.from_installed_gems.search(dep).empty? 
    puts "Installing #{name} #{ver_requirement} ..."
    args = [Config::CONFIG['ruby_install_name'], '-S', 'gem', 'install', name]
    args.unshift('sudo') unless windows?
    args << '-v' << ver_requirement.to_s if ver_requirement
    sh *args
  end
end

# Setup environment for running this Rakefile (RSpec, Docter, etc).
desc "If you're building from sources, run this task one to setup the necessary dependencies."
missing = spec.dependencies.select { |dep| Gem::SourceIndex.from_installed_gems.search(dep).empty? }
task 'setup' do
  missing.each do |dep|
    install_gem dep.name, dep.version_requirements
  end
end
puts "Missing Gems #{missing.join(', ')}, please run rake setup first!" unless missing.empty?
