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


require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helpers'))


module ArchiveTaskHelpers
  # Not too smart, we just create some content based on file name to make sure you read what you write.
  def content_for(file)
    "Content for #{File.basename(file)}"
  end

  # Qualify a filename
  #
  # e.g. qualify("file.zip", "src") => "file-src.zip"
  def qualify(filename, qualifier)
    ext = (filename =~ /\.$/) ? "." : File.extname(filename)
    base = filename[0..0-ext.size-1]
    base + "-" + qualifier + ext
  end

  # Create an archive not using the archive task, this way we do have a file in existence, but we don't
  # have an already invoked task.  Yield an archive task to the block which can use it to include files,
  # set options, etc.
  def create_without_task
    archive(qualify(@archive, "tmp")).tap do |task|
      yield task if block_given?
      task.invoke
      mv task.name, @archive
    end
  end

  def create_for_merge
    zip(qualify(@archive, "src")).include(@files).tap do |task|
      yield task
    end
  end

  def init_dir
    unless @dir
      @dir = File.expand_path('test')
      @files = %w{Test1.txt Text2.html}.map { |file| File.expand_path(file, @dir) }.
        each { |file| write file, content_for(file) }
      @empty_dirs = %w{EmptyDir1 EmptyDir2}.map { |file| File.expand_path(file, @dir) }.
        each { |file| mkdir file }
    end
  end
end

shared_examples_for 'ArchiveTask' do
  include ArchiveTaskHelpers

  before(:each) do
    init_dir
  end

  it 'should point to archive file' do
    expect(archive(@archive).name).to eql(@archive)
  end

  it 'should create file' do
    expect { archive(@archive).invoke }.to change { File.exist?(@archive) }.to(true)
  end

  it 'should create empty archive if no files included' do
    archive(@archive).invoke
    inspect_archive { |archive| expect(archive).to be_empty }
  end

  it 'should raise error when include() is called with nil values' do
    expect { archive(@archive).include(nil) }.to raise_error /called with nil values/
    expect { archive(@archive).include([nil]) }.to raise_error /values should not include nil/
  end

  it 'should create empty archive if called #clean method' do
    archive(@archive).include(@files).clean.invoke
    inspect_archive { |archive| expect(archive).to be_empty }
  end

  it 'should archive all included files' do
    archive(@archive).include(@files).invoke
    inspect_archive { |archive| @files.each { |f| expect(archive[File.basename(f)]).to eql(content_for(f)) } }
    expect(inspect_archive.size).to eql(@files.size)
  end

  it 'should archive file tasks' do
    tasks = @files.map { |fn| file(fn) }
    archive(@archive).include(tasks).invoke
    inspect_archive { |archive| @files.each { |f| expect(archive[File.basename(f)]).to eql(content_for(f)) } }
    expect(inspect_archive.size).to eql(@files.size)
  end

  it 'should invoke and archive file tasks' do
    file = file('included') { write 'included' }
    expect { archive(@archive).include(file).invoke }.to change { File.exist?(file.to_s) }.to(true)
    expect(inspect_archive.keys).to include('included')
  end

  it 'should archive artifacts' do
    write 'library-1.0.txt', 'library-1.0'
    artifact("org.example:library:txt:1.0").from 'library-1.0.txt'
    archive(@archive).include("org.example:library:txt:1.0").invoke
    expect(inspect_archive.keys).to include('library-1.0.txt')
  end

  it 'should archive project artifacts' do
    define 'p1' do
      project.version = '1.0'
      package(:zip)
    end
    archive(@archive).include(project('p1')).invoke
    expect(inspect_archive.keys).to include('p1-1.0.zip')
  end

  it 'should include entry for directory' do
    archive(@archive).include(@dir).invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['test/' + File.basename(f)]).to eql(content_for(f)) } }
  end

  it 'should not archive any excluded files' do
    archive(@archive).include(@files).exclude(@files.last).invoke
    inspect_archive do |archive|
      expect(archive.keys).to include(File.basename(@files.first))
      expect(archive.keys).not_to include(File.basename(@files.last))
    end
  end

  it 'should not archive any excluded files in included directories' do
    archive(@archive).include(@dir).exclude(@files.last).invoke
    inspect_archive do |archive|
      expect(archive.keys).to include('test/' + File.basename(@files.first))
      expect(archive.keys).not_to include('test/' + File.basename(@files.last))
    end
  end

  it 'should not archive any excluded files when using :from/:as' do
    archive(@archive).include(:from=>@dir).exclude(@files.last).invoke
    inspect_archive do |archive|
      expect(archive.keys).to include(File.basename(@files.first))
      expect(archive.keys).not_to include(File.basename(@files.last))
    end
  end

  it 'should raise error when using :from with nil value' do
    expect {
      archive(@archive).include(:from=>nil)
    }.to raise_error /Unrecognized option from/
  end

  it 'should exclude entire directory and all its children' do
    mkpath "#{@dir}/sub"
    write "#{@dir}/sub/test"
    archive(@archive).include(@dir).exclude("#{@dir}/sub").invoke
    inspect_archive do |archive|
      expect(archive.keys.select { |file| file =~ /sub/ }).to be_empty
    end
  end

  it 'should not archive any excluded files when pattern is *.ext' do
    write "test/file.txt"
    write "test/file.swf"
    archive(@archive).include(@dir).exclude('**/*.swf').invoke
    inspect_archive do |archive|
      expect(archive.keys).to include('test/file.txt')
      expect(archive.keys).not_to include('test/file.swf')
    end
  end

  it 'should archive files into specified path' do
    archive(@archive).include(@files, :path=>'code').invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['code/' + File.basename(f)]).to eql(content_for(f)) } }
  end

  it 'should include entry for directory' do
    archive(@archive).include(@dir).invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['test/' + File.basename(f)]).to eql(content_for(f)) } }
  end

  it 'should archive files into specified path' do
    archive(@archive).include(@files, :path=>'code').invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['code/' + File.basename(f)]).to eql(content_for(f)) } }
  end

  it 'should archive directories into specified path' do
    archive(@archive).include(@dir, :path=>'code').invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['code/test/' + File.basename(f)]).to eql(content_for(f)) } }
  end

  it 'should understand . in path' do
    expect(archive(@archive).path('.')).to eq(archive(@archive).path(''))
    expect(archive(@archive).path('foo').path('.')).to eq(archive(@archive).path('foo'))
  end

  it 'should understand .. in path' do
    expect(archive(@archive).path('..')).to eq(archive(@archive).path(''))
    expect(archive(@archive).path('foo').path('..')).to eq(archive(@archive).path(''))
    expect(archive(@archive).path('foo/bar').path('..')).to eq(archive(@archive).path('foo'))
  end

  it 'should understand leading / in path' do
    expect(archive(@archive).path('/')).to eq(archive(@archive).path(''))
    expect(archive(@archive).path('foo/bar').path('/')).to eq(archive(@archive).path(''))
  end

  it 'should archive file into specified name' do
    archive(@archive).include(@files.first, :as=>'test/sample').invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['test/sample']).to eql(content_for(@files.first)) } }
  end

  it 'should archive directory into specified alias, without using "."' do
    archive(@archive).include(@dir, :as=>'.').invoke
    inspect_archive { |archive| expect(archive.keys).not_to include(".") }
  end

  it 'should archive directories into specified alias, even if it has the same name' do
    archive(@archive).include(@dir, :as=>File.basename(@dir)).invoke
    inspect_archive { |archive|
      expect(archive.keys).not_to include "#{File.basename(@dir)}"
    }
  end

  it 'should archive file into specified name/path' do
    archive(@archive).include(@files.first, :as=>'test/sample', :path=>'path').invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['path/test/sample']).to eql(content_for(@files.first)) } }
  end

  it 'should archive files starting with dot' do
    write 'test/.config', '# configuration'
    archive(@archive).include('test').invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['test/.config']).to eql('# configuration') } }
  end

  it 'should archive directory into specified name' do
    archive(@archive).include(@dir, :as=>'code').invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['code/' + File.basename(f)]).to eql(content_for(f)) } }
  end

  it 'should archive directory into specified name/path' do
    archive(@archive).include(@dir, :as=>'code', :path=>'path').invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['path/code/' + File.basename(f)]).to eql(content_for(f)) } }
  end

  it 'should archive directory contents' do
    archive(@archive).include(@dir, :as=>'.').invoke
    inspect_archive { |archive| @files.each { |f| expect(archive[File.basename(f)]).to eql(content_for(f)) } }
  end

  it 'should archive directory contents into specified path' do
    archive(@archive).include(@dir, :as=>'.', :path=>'path').invoke
    inspect_archive { |archive| @files.each { |f| expect(archive['path/' + File.basename(f)]).to eql(content_for(f)) } }
  end

  it 'should not allow two files with the :as argument' do
    expect { archive(@archive).include(@files.first, @files.last, :as=>'test/sample') }.to raise_error(RuntimeError, /one file/)
  end

  it 'should expand another archive file' do
    create_for_merge do |src|
      archive(@archive).merge(src)
      archive(@archive).invoke
      inspect_archive { |archive| @files.each { |f| expect(archive[File.basename(f)]).to eql(content_for(f)) } }
    end
  end

  it 'should expand another archive file with include pattern' do
    create_for_merge do |src|
      archive(@archive).merge(src).include(File.basename(@files.first))
      archive(@archive).invoke
      inspect_archive do |archive|
        expect(archive[File.basename(@files.first)]).to eql(content_for(@files.first))
        expect(archive[File.basename(@files.last)]).to be_nil
      end
    end
  end

  it 'should expand another archive file with exclude pattern' do
    create_for_merge do |src|
      archive(@archive).merge(src).exclude(File.basename(@files.first))
      archive(@archive).invoke
      inspect_archive do |archive|
        @files[1..-1].each { |f| expect(archive[File.basename(f)]).to eql(content_for(f)) }
        expect(archive[File.basename(@files.first)]).to be_nil
      end
    end
  end

  it 'should expand another archive file with nested exclude pattern' do
    @files = %w{Test1.txt Text2.html}.map { |file| File.join(@dir, "foo", file) }.
      each { |file| write file, content_for(file) }
    zip(qualify(@archive, "src")).include(@dir).tap do |task|
      archive(@archive).merge(task).exclude('test/*')
      archive(@archive).invoke
      expect(inspect_archive).to be_empty
    end
  end

  it 'should expand another archive file into path' do
    create_for_merge do |src|
      archive(@archive).path('test').merge(src)
      archive(@archive).invoke
      inspect_archive { |archive| @files.each { |f| expect(archive['test/' + File.basename(f)]).to eql(content_for(f)) } }
    end
  end

  it 'should expand another archive file into path with :path option' do
    create_for_merge do |src|
      archive(@archive).merge(src, :path=>'test')
      archive(@archive).invoke
      inspect_archive { |archive| @files.each { |f| expect(archive['test/' + File.basename(f)]).to eql(content_for(f)) } }
    end
  end

  it "should expand another archive file into path with :path=>'/'" do
    create_for_merge do |src|
      archive(@archive).merge(src, :path=>'/')
      archive(@archive).invoke
      inspect_archive { |archive| @files.each { |f| expect(archive[File.basename(f)]).to eql(content_for(f)) } }
    end
  end

  it 'should expand another archive file into path with merge option' do
    create_for_merge do |src|
      archive(@archive).include(src, :merge=>true)
      archive(@archive).invoke
      inspect_archive { |archive| @files.each { |f| expect(archive[File.basename(f)]).to eql(content_for(f)) } }
    end
  end

  it 'should update if one of the files is recent' do
    create_without_task { |archive| archive.include(@files) }
    # Touch archive file to some point in the past. This effectively makes
    # all included files newer.
    File.utime Time.now - 100, Time.now - 100, @archive
    archive(@archive).include(@files).invoke
    expect(File.stat(@archive).mtime).to be_within(10).of(Time.now)
  end

  it 'should update if a file in a subdir is more recent' do
    subdir = File.expand_path("subdir", @dir)
    test3 = File.expand_path("test3.css", subdir)

    mkdir_p subdir
    write test3, '/* Original */'

    create_without_task { |archive| archive.include(:from => @dir) }
    inspect_archive { |archive| expect(archive["subdir/test3.css"]).to eql('/* Original */') }

    write test3, '/* Refreshed */'
    File.utime(Time.now + 100, Time.now + 100, test3)
    archive(@archive).include(:from => @dir).invoke
    inspect_archive { |archive| expect(archive["subdir/test3.css"]).to eql('/* Refreshed */') }
   end

  it 'should do nothing if all files are uptodate' do
    create_without_task { |archive| archive.include(@files) }
    # By touching all files in the past, there's nothing new to update.
    (@files + [@archive]).each { |f| File.utime Time.now - 100, Time.now - 100, f }
    archive(@archive).include(@files).invoke
    expect(File.stat(@archive).mtime).to be_within(10).of(Time.now - 100)
  end

  it 'should update if one of the files is recent' do
    create_without_task { |archive| archive.include(@files) }
    # Change files, we expect to see new content.
    write @files.first, '/* Refreshed */'
    File.utime(Time.now - 100, Time.now - 100, @archive) # Touch archive file to some point in the past.
    archive(@archive).include(@files).invoke
    inspect_archive { |archive| expect(archive[File.basename(@files.first)]).to eql('/* Refreshed */') }
  end

  it 'should create new archive when updating' do
    create_without_task { |archive| archive.include(@files) }
    File.utime(Time.now - 100, Time.now - 100, @archive) # Touch archive file to some point in the past.
    archive(@archive).include(@files[1..-1]).invoke
    expect(inspect_archive.size).to be(@files.size - 1)
  end

  it 'should not accept invalid options' do
    archive(@archive).include(@files)
    expect { archive(@archive).with :option=>true }.to raise_error /does not support the option option/
  end

  it 'should invoke paths supplied in from parameters' do
    included_file = File.expand_path("somefile.myext")
    write included_file, content_for(included_file)
    archive2_filename = File.expand_path("somebug.zip")
    a2 = zip(archive2_filename).
      include(included_file, :as => 'folder1/somefile1.ext').
      include(included_file, :as => 'folder2/somefile2.ext').
      invoke
    a = archive(@archive)
    f1 = unzip('target/folder1' => archive2_filename).from_path("folder1/*").root
    f2 = unzip('target/folder2' => archive2_filename).from_path("folder2/*").root
    a.include(:from => f1)
    a.include(:from => f2)
    a.invoke
    contents = inspect_archive
    expect(contents["folder1/somefile1.ext"]).not_to be_nil
    expect(contents["folder2/somefile2.ext"]).not_to be_nil
  end
end

describe TarTask do
  it_should_behave_like 'ArchiveTask'

  before(:each) do
    @archive = File.expand_path('test.tar')
  end

  define_method(:archive) { |file| tar(file) }

  def inspect_archive
    entries = {}
    Archive::Tar::Minitar.open @archive, 'r' do |reader|
      reader.each { |entry| entries[entry.directory ? "#{entry.name}/" : entry.name] = entry.read }
    end
    yield entries if block_given?
    entries
  end

  # chmod is not reliable on Windows
  unless Buildr::Util.win_os?
    it 'should preserve file permissions' do
      # with JRuby it's important to use absolute paths with File.chmod()
      # http://jira.codehaus.org/browse/JRUBY-3300
      hello = File.expand_path('src/main/bin/hello')
      write hello, 'echo hi'
      File.chmod(0777,  hello)
      fail("Failed to set permission on #{hello}") unless (File.stat(hello).mode & 0777) == 0777

      tar('foo.tgz').include('src/main/bin/*').invoke
      unzip('target' => 'foo.tgz').extract
      expect(File.stat('target/hello').mode & 0777).to eq(0777)
    end

    it 'should preserve file permissions when merging zip files' do
      # with JRuby it's important to use absolute paths with File.chmod()
      # http://jira.codehaus.org/browse/JRUBY-3300
      hello = File.expand_path('src/main/bin/hello')
      write hello, 'echo hi'
      File.chmod(0777,  hello)
      fail("Failed to set permission on #{hello}") unless (File.stat(hello).mode & 0777) == 0777

      foo = zip('foo.zip')
      foo.include('src/main/bin/*').invoke
      bar = tar('bar.tgz')
      bar.merge(foo)
      bar.invoke
      unzip('target' => 'bar.tgz').extract
      expect(File.stat('target/hello').mode & 0777).to eq(0777)
    end
  end

end


describe TarTask, ' gzipped' do
  it_should_behave_like 'ArchiveTask'

  before(:each) do
    @archive = File.expand_path('test.tgz')
  end

  define_method(:archive) { |file| tar(file) }

  def inspect_archive
    entries = {}
    Zlib::GzipReader.open @archive do |gzip|
      Archive::Tar::Minitar.open gzip, 'r' do |reader|
        reader.each { |entry| entries[entry.directory ? "#{entry.name}/" : entry.name] = entry.read }
      end
    end
    yield entries if block_given?
    entries
  end
end

describe "ZipTask" do
  include ArchiveTaskHelpers

  it_should_behave_like 'ArchiveTask'

  before(:each) do
    init_dir
    @archive = File.expand_path('test.zip')
  end

  define_method(:archive) { |file| zip(file) }

  after(:each) do
    checkZip(@archive)
  end

  # Check for possible corruption using Java's ZipInputStream and Java's "jar" command since
  # they are stricter than rubyzip
  def checkZip(file)
    return unless File.exist?(file)
    zip = Java.java.util.zip.ZipInputStream.new(Java.java.io.FileInputStream.new(file))
    zip_entry_count = 0
    while entry = zip.getNextEntry do
      # just iterate over all entries
      zip_entry_count = zip_entry_count + 1
    end
    zip.close()

    # jar tool fails with "ZipException: error in opening zip file" if empty
    if zip_entry_count > 0
      sh "#{File.join(ENV['JAVA_HOME'], 'bin', 'jar')} tvf #{file}"
    end
  end

  def inspect_archive
    entries = {}
    Zip::File.open @archive do |zip|
      zip.entries.each do |entry|
        if entry.directory?
          # Ignore the / directory created for empty ZIPs when using java.util.zip.
          if entry.name.to_s != '/'
            entries[entry.name.to_s] = nil
          end
        else
          entries[entry.name.to_s] = zip.read(entry.name)
        end
      end
    end
    yield entries if block_given?
    entries
  end

  it 'should include empty dirs' do
    archive(@archive).include(@dir)
    archive(@archive).invoke
    inspect_archive do |archive|
      expect(archive.keys).to include('test/EmptyDir1/')
    end
  end

  it 'should include empty dirs from Dir' do
    archive(@archive).include(Dir["#{@dir}/*"])
    archive(@archive).invoke
    inspect_archive do |archive|
      expect(archive.keys).to include('EmptyDir1/')
    end
  end

  it 'should work with path object' do
    archive(@archive).path('code').include(@files)
    archive(@archive).invoke
    inspect_archive { |archive| expect(archive.keys).to include('code/') }
  end

  it 'should have path object that includes empty dirs' do
    archive(@archive).path('code').include(Dir["#{@dir}/*"])
    archive(@archive).invoke
    inspect_archive do |archive|
      expect(archive.keys).to include('code/EmptyDir1/')
    end
  end

  # chmod is not reliable on Windows
  unless Buildr::Util.win_os?
    it 'should preserve file permissions' do
      # with JRuby it's important to use absolute paths with File.chmod()
      # http://jira.codehaus.org/browse/JRUBY-3300
      hello = File.expand_path('src/main/bin/hello')
      write hello, 'echo hi'
      File.chmod(0777,  hello)
      fail("Failed to set permission on #{hello}") unless (File.stat(hello).mode & 0777) == 0777

      zip('foo.zip').include('src/main/bin/*').invoke
      unzip('target' => 'foo.zip').extract
      expect(File.stat('target/hello').mode & 0777).to eq(0777)
    end

    it 'should preserve file permissions when merging zip files' do
      # with JRuby it's important to use absolute paths with File.chmod()
      # http://jira.codehaus.org/browse/JRUBY-3300
      hello = File.expand_path('src/main/bin/hello')
      write hello, 'echo hi'
      File.chmod(0777,  hello)
      fail("Failed to set permission on #{hello}") unless (File.stat(hello).mode & 0777) == 0777

      foo = zip('foo.zip')
      foo.include('src/main/bin/*').invoke
      bar = zip('bar.zip')
      bar.merge(foo)
      bar.invoke
      unzip('target' => 'bar.zip').extract
      expect(File.stat('target/hello').mode & 0777).to eq(0777)
    end
  end

end

describe Unzip do
  before(:each) do
    @zip = File.expand_path('test.zip')
    @dir = File.expand_path('test')
    @files = %w{Test1.txt Text2.html}.map { |file| File.join(@dir, file) }.
      each { |file| write file, content_for(file) }
    @target = File.expand_path('target')
    @targz = File.expand_path('test.tar.gz')
    @targz2 = File.expand_path('test.tgz')
  end

  # Not too smart, we just create some content based on file name to
  # make sure you read what you write.
  def content_for(file)
    "Content for #{File.basename(file)}"
  end

  def with_tar(*args)
    tar(@targz).include(*args.empty? ? @files : args).invoke
    yield
  end

  def with_tar_too(*args)
    tar(@targz2).include(*args.empty? ? @files : args).invoke
    yield
  end

  def with_zip(*args)
    zip(@zip).include(*args.empty? ? @files : args).invoke
    yield
  end

  it 'should touch target directory' do
    with_zip do
      mkdir @target
      File.utime(Time.now - 10, Time.now - 10, @target)
      unzip(@target=>@zip).target.invoke
    end
    expect(File.stat(@target).mtime).to be_within(2).of(Time.now)
  end

  it 'should expand files' do
    with_zip do
      unzip(@target=>@zip).target.invoke
      @files.each { |f| expect(File.read(File.join(@target, File.basename(f)))).to eql(content_for(f)) }
    end
  end

  it 'should expand files from a tar.gz file' do
    with_tar do
      unzip(@target=>@targz).target.invoke
      @files.each { |f| expect(File.read(File.join(@target, File.basename(f)))).to eql(content_for(f)) }
    end
  end

  it 'should expand files from a .tgz file' do
    with_tar_too do
      unzip(@target=>@targz2).target.invoke
      @files.each { |f| expect(File.read(File.join(@target, File.basename(f)))).to eql(content_for(f)) }
    end
  end

  it 'should expand all files' do
    with_zip do
      unzip(@target=>@zip).target.invoke
      expect(FileList[File.join(@target, '*')].size).to be(@files.size)
    end
  end

  it 'should expand all files from a .tar.gz file' do
    with_tar do
      unzip(@target=>@targz).target.invoke
      expect(FileList[File.join(@target, '*')].size).to be(@files.size)
    end
  end

  it 'should expand only included files' do
    with_zip do
      only = File.basename(@files.first)
      unzip(@target=>@zip).include(only).target.invoke
      expect(FileList[File.join(@target, '*')]).to include(File.expand_path(only, @target))
      expect(FileList[File.join(@target, '*')].size).to be(1)
    end
  end

  it 'should expand only included files from a .tar.gz file' do
    with_tar do
      only = File.basename(@files.first)
      unzip(@target=>@targz).include(only).target.invoke
      expect(FileList[File.join(@target, '*')]).to include(File.expand_path(only, @target))
      expect(FileList[File.join(@target, '*')].size).to be(1)
    end
  end

  it 'should expand all but excluded files' do
    with_zip do
      except = File.basename(@files.first)
      unzip(@target=>@zip).exclude(except).target.invoke
      expect(FileList[File.join(@target, '*')]).not_to include(File.expand_path(except, @target))
      expect(FileList[File.join(@target, '*')].size).to be(@files.size - 1)
    end
  end

  it 'should expand all but excluded files with a .tar.gz file' do
    with_tar do
      except = File.basename(@files.first)
      unzip(@target=>@targz).exclude(except).target.invoke
      expect(FileList[File.join(@target, '*')]).not_to include(File.expand_path(except, @target))
      expect(FileList[File.join(@target, '*')].size).to be(@files.size - 1)
    end
  end

  it 'should include with nested path patterns' do
    with_zip @files, :path=>'test/path' do
      only = File.basename(@files.first)
      unzip(@target=>@zip).include(only).target.invoke
      expect(FileList[File.join(@target, '*')]).to be_empty

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@zip).include('test/path/' + only).target.invoke
      expect(FileList[File.join(@target, 'test/path/*')].size).to be(1)

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@zip).include('test/**/*').target.invoke
      expect(FileList[File.join(@target, 'test/path/*')].size).to be(2)

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@zip).include('test/*').target.invoke
      expect(FileList[File.join(@target, 'test/path/*')].size).to be(2)
    end
  end

  it 'should include with nested path patterns with a .tar.gz file' do
    with_tar @files, :path=>'test/path' do
      only = File.basename(@files.first)
      unzip(@target=>@targz).include(only).target.invoke
      expect(FileList[File.join(@target, '*')]).to be_empty

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@targz).include('test/path/' + only).target.invoke
      expect(FileList[File.join(@target, 'test/path/*')].size).to be(1)

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@targz).include('test/**/*').target.invoke
      expect(FileList[File.join(@target, 'test/path/*')].size).to be(2)
    end
  end

  it 'should include with relative path' do
    with_zip @files, :path=>'test/path' do
      only = File.basename(@files.first)
      unzip(@target=>@zip).tap { |unzip| unzip.from_path('test').include(only) }.target.invoke
      expect(FileList[File.join(@target, '*')]).to be_empty

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@zip).tap { |unzip| unzip.from_path('test').include('test/*') }.target.invoke
      expect(FileList[File.join(@target, 'path/*')]).to be_empty

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@zip).tap { |unzip| unzip.from_path('test').include('path/*' + only) }.target.invoke
      expect(FileList[File.join(@target, 'path/*')].size).to be(1)

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@zip).tap { |unzip| unzip.from_path('test').include('path/*') }.target.invoke
      expect(FileList[File.join(@target, 'path/*')].size).to be(2)
    end
  end

  it 'should include with relative path with a .tar.gz file' do
    with_tar @files, :path=>'test/path' do
      only = File.basename(@files.first)
      unzip(@target=>@targz).tap { |unzip| unzip.from_path('test').include(only) }.target.invoke
      expect(FileList[File.join(@target, '*')]).to be_empty

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@targz).tap { |unzip| unzip.from_path('test').include('test/*') }.target.invoke
      expect(FileList[File.join(@target, 'path/*')]).to be_empty

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@targz).tap { |unzip| unzip.from_path('test').include('path/*' + only) }.target.invoke
      expect(FileList[File.join(@target, 'path/*')].size).to be(1)

      Rake::Task.clear ; rm_rf @target
      unzip(@target=>@targz).tap { |unzip| unzip.from_path('test').include('path/*') }.target.invoke
      expect(FileList[File.join(@target, 'path/*')].size).to be(2)
    end
  end

  it 'should exclude with relative path' do
    with_zip @files, :path=>'test' do
      except = File.basename(@files.first)
      unzip(@target=>@zip).tap { |unzip| unzip.from_path('test').exclude(except) }.target.invoke
      expect(FileList[File.join(@target, '*')]).to include(File.join(@target, File.basename(@files[1])))
      expect(FileList[File.join(@target, '*')].size).to be(@files.size - 1)
    end
  end

  it 'should exclude with relative path on a tar.gz file' do
    with_tar @files, :path=>'test' do
      except = File.basename(@files.first)
      unzip(@target=>@targz).tap { |unzip| unzip.from_path('test').exclude(except) }.target.invoke
      expect(FileList[File.join(@target, '*')]).to include(File.join(@target, File.basename(@files[1])))
      expect(FileList[File.join(@target, '*')].size).to be(@files.size - 1)
    end
  end

  it "should handle relative paths without any includes or excludes" do
    lib_files = %w{Test3.so Test4.rb}.
      map { |file| File.join(@dir, file) }.
      each { |file| write file, content_for(file) }
    zip(@zip).include(@files, :path => 'src').include(lib_files, :path => 'lib').invoke

    unzip(@target=>@zip).tap { |unzip| unzip.from_path('lib') }.target.invoke
    expect(FileList[File.join(@target, '**/*')].size).to eq(2)
  end

  it "should handle relative paths without any includes or excludes with a tar.gz file" do
    lib_files = %w{Test3.so Test4.rb}.
      map { |file| File.join(@dir, file) }.
      each { |file| write file, content_for(file) }
    tar(@targz).include(@files, :path => 'src').include(lib_files, :path => 'lib').invoke

    unzip(@target=>@targz).tap { |unzip| unzip.from_path('lib') }.target.invoke
    expect(FileList[File.join(@target, '**/*')].size).to eq(2)
  end

  it 'should return itself from root method' do
    task = unzip(@target=>@zip)
    expect(task.root).to be(task)
    expect(task.from_path('foo').root).to be(task)
  end

  it 'should return target task from target method' do
    task = unzip(@target=>@zip)
    expect(task.target).to be(file(@target))
    expect(task.from_path('foo').target).to be(file(@target))
  end

  it 'should alias from_path as path' do
    task = unzip(@target=>@zip)
    expect(task.from_path('foo')).to be(task.path('foo'))
  end

end
