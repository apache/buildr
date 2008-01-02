require File.join(File.dirname(__FILE__), 'sandbox')


describe 'Local directory build task' do
  it 'should execute build task for current project' do
    define 'foobar'
    lambda { task('build').invoke }.should run_task('foobar:build')
  end

  it 'should not execute build task for other projects' do
    define 'foobar', :base_dir=>'elsewhere'
    lambda { task('build').invoke }.should_not run_task('foobar:build')
  end
end


describe Project, ' build task' do
  it 'should execute build task for sub-project' do
    define('foo') { define 'bar' }
    lambda { task('foo:build').invoke }.should run_task('foo:bar:build')
  end

  it 'should not execute build task of other projects' do
    define 'foo'
    define 'bar'
    lambda { task('foo:build').invoke }.should_not run_task('bar:build')
  end

  it 'should be accessible as build method' do
    define 'boo'
    project('boo').build.should be(task('boo:build'))
  end
end


describe Project, 'target' do
  before :each do
    @project = define('foo', :layout=>Layout.new)
  end

  it 'should default to target' do
    @project.target.should eql('target')
  end

  it 'should set layout :target' do
    @project.target = 'bar'
    @project.layout.expand(:target).should eql(File.expand_path('bar'))
  end

  it 'should come from layout :target' do
    @project.layout[:target] = 'baz'
    @project.target.should eql('baz')
  end
end


describe Project, 'reports' do
  before :each do
    @project = define('foo', :layout=>Layout.new)
  end

  it 'should default to reports' do
    @project.reports.should eql('reports')
  end

  it 'should set layout :reports' do
    @project.reports = 'bar'
    @project.layout.expand(:reports).should eql(File.expand_path('bar'))
  end

  it 'should come from layout :reports' do
    @project.layout[:reports] = 'baz'
    @project.reports.should eql('baz')
  end
end
