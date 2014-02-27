require File.dirname(__FILE__) + '/../test_helper'
require File.dirname(__FILE__) + '/spy_disk'
require File.dirname(__FILE__) + '/stub_git'
require File.dirname(__FILE__) + '/stub_time_boxed_task'


class SandboxTests < ActionController::TestCase

  def setup
    Thread.current[:disk] = @disk = SpyDisk.new
    Thread.current[:git] = @git = StubGit.new
    Thread.current[:task] = @stub_task = StubTimeBoxedTask.new
    @dojo = Dojo.new('spied')
    @id = '45ED23A2F1'
    @kata = @dojo[@id]
    @avatar = @kata['hippo']
    @sandbox = @avatar.sandbox
  end

  def teardown
    @disk.teardown
    Thread.current[:disk] = nil
    Thread.current[:git] = nil
    Thread.current[:task] = nil
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  test "when no disk on thread the ctor raises" do
    Thread.current[:disk] = nil
    error = assert_raises(RuntimeError) { Sandbox.new(nil) }
    assert_equal "no disk", error.message
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  test "when no git on thread the ctor raises" do
    Thread.current[:git] = nil
    error = assert_raises(RuntimeError) { Sandbox.new(nil) }
    assert_equal "no git", error.message
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  test "path ends in slash" do
    assert @sandbox.path.end_with?(@disk.dir_separator)
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  test "path does not have doubled separator" do
    doubled_separator = @disk.dir_separator * 2
    assert_equal 0, @sandbox.path.scan(doubled_separator).length
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  test "dir is not created until file is saved" do
    assert !@sandbox.dir.exists?
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  test "after run_tests() a file called output is saved in sandbox " +
         "and an output file is not inserted into the visible_files argument" do
    visible_files = {
      'untitled.c' => 'content for code file',
      'untitled.test.c' => 'content for test file',
      'cyber-dojo.sh' => 'make'
    }
    assert !visible_files.keys.include?('output')
    delta = {
      :changed => [ 'untitled.c' ],
      :unchanged => [ 'untitled.test.c' ],
      :deleted => [ ],
      :new => [ ]
    }
    @sandbox.write(delta, visible_files)
    output = @sandbox.test()
    assert_equal "stubbed-output", output
    @avatar.sandbox.dir.write('output', output) # so output appears in diff-view

    assert !visible_files.keys.include?('output')
    assert output.class == String, "output.class == String"
    assert_equal ['write','output',output], @sandbox.dir.log.last
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  test "write():delta[:changed] files are saved" do
    visible_files = {
      'untitled.cs' => 'content for code file',
      'untitled.test.cs' => 'content for test file',
      'cyber-dojo.sh' => 'gmcs'
    }
    delta = {
      :changed => [ 'untitled.cs', 'untitled.test.cs'  ],
      :unchanged => [ ],
      :deleted => [ ],
      :new => [ ]
    }
    @sandbox.write(delta, visible_files)
    @output = @sandbox.test()
    @sandbox.dir.write('output', @output)

    log = @sandbox.dir.log
    saved_files = filenames_written_to_in(log)
    assert_equal ['output', 'untitled.cs', 'untitled.test.cs'], saved_files.sort
    assert log.include?(['write','untitled.cs', 'content for code file' ]), log.inspect
    assert log.include?(['write','untitled.test.cs', 'content for test file' ]), log.inspect
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  test "write():delta[:unchanged] files are not saved" do
    visible_files = {
      'untitled.cs' => 'content for code file',
      'untitled.test.cs' => 'content for test file',
      'cyber-dojo.sh' => 'gmcs'
    }
    delta = {
      :changed => [ 'untitled.cs' ],
      :unchanged => [ 'cyber-dojo.sh', 'untitled.test.cs' ],
      :deleted => [ ],
      :new => [ ]
    }
    @sandbox.write(delta, visible_files)
    saved_files = filenames_written_to_in(@sandbox.dir.log)
    assert !saved_files.include?('cyber-dojo.sh'), saved_files.inspect
    assert !saved_files.include?('untitled.test.cs'), saved_files.inspect
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  test "write():delta[:new] files are saved and git added" do
    visible_files = {
      'wibble.cs' => 'content for code file',
      'untitled.test.cs' => 'content for test file',
      'cyber-dojo.sh' => 'gmcs'
    }
    delta = {
      :changed => [ ],
      :unchanged => [ 'cyber-dojo.sh', 'untitled.test.cs' ],
      :deleted => [ ],
      :new => [ 'wibble.cs' ]
    }
    @sandbox.write(delta, visible_files)
    saved_files = filenames_written_to_in(@sandbox.dir.log)
    assert saved_files.include?('wibble.cs'), saved_files.inspect

    git_log = @git.log[@sandbox.path]
    assert git_log.include?([ 'add', 'wibble.cs' ]), git_log.inspect
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  test "write():delta[:deleted] files are git rm'd" do
    visible_files = {
      'untitled.cs' => 'content for code file',
      'untitled.test.cs' => 'content for test file',
      'cyber-dojo.sh' => 'gmcs'
    }
    delta = {
      :changed => [ 'untitled.cs' ],
      :unchanged => [ 'cyber-dojo.sh', 'untitled.test.cs' ],
      :deleted => [ 'wibble.cs' ],
      :new => [ ]
    }
    @sandbox.write(delta, visible_files)
    saved_files = filenames_written_to_in(@sandbox.dir.log)
    assert !saved_files.include?('wibble.cs'), saved_files.inspect

    git_log = @git.log[@sandbox.path]
    assert git_log.include?([ 'rm', 'wibble.cs' ]), git_log.inspect
  end

  #- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

  def filenames_written_to_in(log)
    # each log entry is of the form
    #  [ 'read'/'write',  filename, content ]
    log.select { |entry| entry[0] == 'write' }.collect{ |entry| entry[1] }
  end

end
