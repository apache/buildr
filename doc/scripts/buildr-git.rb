# This script helps buildr developers to obtain their own git clone from
# github, having a set of pre-defined aliases to work with Apache's SVN.
#
# You dont need to have a buildr copy to use it, just execute the buildr-git balloon:
#
#   ruby -ropen-uri -e 'eval(open("http://balloon.hobix.com/buildr-git").read)'

require 'yaml'
require 'optparse'
require 'ostruct'

# Pager from http://nex-3.com/posts/73-git-style-automatic-paging-in-ruby
def run_pager
  return if PLATFORM =~ /win32/
  return unless STDOUT.tty?

  read, write = IO.pipe

  unless Kernel.fork # Child process
    STDOUT.reopen(write)
    STDERR.reopen(write) if STDERR.tty?
    read.close
    write.close
    return
  end

  # Parent process, become pager
  STDIN.reopen(read)
  read.close
  write.close

  ENV['LESS'] = 'FSRX' # Don't page if the input is short enough

  Kernel.select [STDIN] # Wait until we have input before we start the pager
  pager = ENV['PAGER'] || 'less'
  exec pager rescue exec "/bin/sh", "-c", pager
end

def header
  <<HEADER

Buildr official commit channel is Apache's svn repository, however some
developers may prefer to use git while working on several features and
merging other's changes.

This script will configure a buildr-git copy on so you can commit to svn.

Enter <-h> to see options, <-H> to see notes about configured aliases
and recommended workflow, or any other option.

Ctrl+D or an invalid option to abort
HEADER
end

def notice
  <<NOTICE
ALIASES:

  Some git aliases have been created for developer convenience:

    git apache-fetch    # get changes from apache/trunk without merging them
                        # you can inspect what's happening on trunk without
                        # having to worry about merging conflicts.
                        # Inspect the remote branch with `git log apache/trunk`
                        # Or if you have a git-ui like `tig` you can use that.

    git apache-merge    # Merge already fetched changes on the current branch
                        # Use this command to get up to date with trunk changes
                        # you can always cherry-pick from the apache/trunk 
                        # branch.

    git apache-pull     # get apache-fetch && git apache-merge
   
    git apache-push     # Push to Apache's SVN. Only staged changes (those 
                        # recorded using `git commit`) will be sent to SVN. 
                        # You need not to be on the master branch.
                        # Actually you can work on a tiny-feature branch and
                        # commit directly from it. 
                        #
                        # VERY IMPORTANT: 
                        #
                        # Missing commits on Apache's SVN will be sent using
                        # your apache svn account. This means that you can
                        # make some commits on behalf of others (like patches
                        # comming from JIRA issues or casual contributors)
                        # Review the apache-push alias on .git/config if you 
                        # want to change login-name used for commit to SVN.
                        # 
                        # See the recommended workflow to avoid commiting 
                        # other developers' changes and the following section.

THE GITHUB MIRROR:

   Buildr has an unofficial git mirror on github, maintained by Victor: 

     http://github.com/vic/buildr

   Actually it's not Victor who manually updates it, he has a cron-job on his
   server, that only runs

     git synchronize 

   A command you also have configured on your .git/config file.

   However there are some limitations due to the fact that git-svn cannot 
   commit as multiple authors (unless all of them provided their passwords
   to Victor, yet he doesn't want to take over the world.)
   This means that if a commit is pushed to vic/buildr/master and has not
   already been pushed by YOU to Apache's SVN by using `git apache-push` 
   your change will be commited to apache/trunk having Victor as the author
   (that's how he gains meritocratic points at Apache :P). 

   So, it's very important - if you care about meritocracy - to follow or at 
   least that you get an idea of the recommended workflow.

RECOMMENDED WORKFLOW:
   
   So now that you have your local buildr copy you can create topic branches 
   to work on independent features, and still merge easily with head changes. 

   They may seem lots of things to consider, but it's all for Buildr's healt.
   As all things git, you can always follow your own workflow and even create
   aliases on you .git/config file to avoid typing much. So, here they are:

   1) get your buildr-git configured 
     (you have already do so, this was the most difficult part)

   2) create a topic branch to work on, say.. you want to add cool-feature:

        git checkout -b cool-feature master 
        # now on branch cool-feature

   3) hack hack hack.. use the source luke.
      every time you feel you have something important like added failing 
      spec, added part of feature, or resolved some conflict from merges,
      you can commit your current progress. If you want to be selective, use: 
      
        git commit --interactive

   3) review your changes, get ALL specs passing, repeat step 3 as needed

   4) let's see what are they doing on trunk

        git apache-fetch
        # You can inspect the upstream changes without having to merge them
        git log apache/trunk # what are they doing!!
      
   5) integrate mainstream changes to your cool-feature branch, you can always
      use `git cherry-pick` to select only some commits.

        git merge apache/trunk cool-feature
   
   6) Go to 3 unless ALL specs are passing.

   7.a) (Skip to 7.b you have commit bit on Apache's SVN)
      Create a patch using `git format-patch`
      Promote your changes, create a JIRA issue and upload it granting Apache
      license to include your code:

        https://issues.apache.org/jira/browse/BUILDR
        buildr-dev@incubator.apache.org

   7.b) Now you have everyhing on staging area and merged important changes 
      from apache/trunk, it's time to commit them to Apache's SVN.

        git apache-push 

   8) Optional. If you can push to vic/buildr/master mirror, you can just 
     synchronize the mirror helping others to get changes without having to 
     wait on Victor's cronjob to run every hour (useful for urgent changes).

        git synchronize

   9) Pull changes from origin frequently.
        
        git fetch origin
        git rebase --onto origin/master master master

   10) Unconditionally, Go to step 2 ;)
       Share your buildr-git workflow, git tips, etc.

RESOURCES:

   http://github.com/vic/buildr/tree/master
   http://git.or.cz/gitwiki/GitCheatSheet
   http://groups.google.com/group/git-users/web/git-references

NOTICE
end # notice method

def optparse(options = OpenStruct.new, argv = ARGV)
  opt = OptionParser.new do |opt|
    
    if `git status 2>/dev/null`.chomp.empty?
      options.local = File.expand_path('buildr', Dir.pwd)
    else
      puts "Current directory is a git repo: #{Dir.pwd}"
      options.local = Dir.pwd 
    end

    options.svn_branch = "apache/trunk"
    options.origin = "git://github.com/vic/buildr.git"
    options.member = false

    opt.banner = "Usage: buildr-git.rb [options]"
    opt.separator ""
    opt.separator "OPTIONS:"

    opt.on('-a', "--anon", "Use git://github.com/vic/buildr.git as origin") do 
      options.origin = "git://github.com/vic/buildr.git"
    end
    opt.on('-A', "--auth", "Use git@github.com:vic/buildr.git as origin") do
      options.origin = "git@github.com:vic/buildr.git"
    end
    opt.on("-o", "--origin GIT_URL", "Clone from GIT_URL origin") do |value|
      options.origin = value
    end
    opt.on('-l', "--local DIRECTORY", "Create local git clone on DIRECTORY") do |value|
      options.local = value
    end
    opt.on('-b', "--branch GIT_SVN_BRANCH", 
           "Set the name for svn branch instead of apache/trunk") do |value|
      options.svn_branch = value
    end
    opt.on('-e', "--email EMAIL", 
           "Configure git to use EMAIL for commits") do |value|
      options.email = value
    end
    opt.on('-n', "--name USER_NAME", 
           "Configure your USER_NAME for git commits") do |value|
      options.user_name = value
    end
    opt.on('-h', "--help", "Show buildr-git help") do 
      puts opt
      throw :exit
    end
    opt.on('-H', "--notice", "Show notice about aliases and git workflow") do
      run_pager
      puts notice
      throw :exit
    end
  end
  opt.parse!(argv)
  options
end # optparse method


def main
  catch :exit do
    options = optparse
    puts header
    puts 
    print '> '
    if input = gets
      options = optparse(options, input.split)
    end
    if input.nil? || (input != "\n" && input.empty?)
      puts "Aborting."
      return
    end
    perform(options)
  end  
end

def perform(options)
  origin = options.origin
  member = origin =~ /@/
  local = options.local
  svn_branch = options.svn_branch
  user_email = options.email
  user_name = options.user_name
  
  `git clone #{origin} #{local} 1>&2` unless File.directory?(File.join('.git', origin))
  
  puts
  puts "Entering #{local} directory"
  puts
  Dir.chdir(local) do
    
    # Load the list of git-svn committers
    svn_authors_file = File.expand_path('etc/git-svn-authors', Dir.pwd)
    svn_authors = File.read(svn_authors_file)
    svn_authors.gsub!(/\s+=\s+/, ': ')
    svn_authors = YAML.load(svn_authors)

    # set the git-svn-authors file
    `git config svn.authorsfile "#{svn_authors_file}"`

    # Check that git is configured for the developer
    user_email ||= `git config --get user.email`.chomp
    if user_email.empty?
      if member
        puts "Enter your email as listed on #{svn_authors_file}"
        print "> "
        user_email = gets.chomp
      else
        puts "Provide an email address for git usage:"
        user_email = gets.chomp
      end
    end

    # Check user is listed
    unless user_email.empty?
      svn_user, git_contact = *svn_authors.find { |entry| /#{user_email}/ === entry.join(' ') }
    end

    if member 
      if git_contact.nil? # if using the authenticated git, he must be listed
        puts <<-NOTICE
          You need to be a buildr commmitter listed on #{svn_authors_file}. 
          Perhaps you need to add yourself to it, commit it using SVN, and 
          and run this script again.
          Also checks your git global values for user.email and user.name
        NOTICE
        return
      elsif /\s*(.*?)\s+\<(.+)\>\s*/ === git_contact
        user_name, user_email = $1, $2
      else
        puts "Invalid contact string for #{svn_user}: #{git_contact.inspect}"
        return
      end
    elsif user_email =~ /^\s*$/
      puts "User email shall not include spaces: #{user_email.inspect}"
      return
    end
    
    user_name ||= `git config --get user.name`.chomp
    if git_contact.nil? && user_name.empty?
      puts "Provide a developer name for git usage:"
      user_name = gets.chomp
    end
    
    # Start the pager
    run_pager
    puts


    old_origin = `git config --get remote.origin.url`.chomp
    if member && old_origin !~ /@/
      puts "Switching to authenticated origin #{origin}", ""
      `git config remote.origin.url "#{origin}"`
    elsif !member && old_origin =~ /@/
      puts "Switching to anonymous origin #{origin}", ""
      `git config remote.origin.url "#{origin}"`
    end
    
    # Configure user name and email for git sake (and github's gravatar)
    puts "You claim to be #{user_name.inspect} <#{user_email}> "
    puts "with apache-svn user: #{svn_user}" if svn_user
    puts
    `git config user.name  "#{user_name}"`
    `git config user.email "#{user_email}"`
    
    # Ok, now obtain the last svn commit from history
    last_svn_log = `git log -n 10 | grep git-svn-id | head -n 1`
    fail "No svn metadata on last 10 commits" unless last_svn_log =~ /git-svn-id/
    svn_repo, svn_prev = last_svn_log.split[1].split("@")
    
    # Tell git where the svn repository is.
    `git config svn-remote.#{svn_branch}.url #{svn_repo}`
    `git config svn-remote.#{svn_branch}.fetch :refs/remotes/#{svn_branch}`
    
    # Create the svn branch, do this instead of pulling the full svn history
    `git push --force . refs/remotes/origin/master:refs/remotes/#{svn_branch}`
    
    # Create apache aliases for developers git-workflow.
    `git config alias.apache-fetch "!git-svn fetch #{svn_branch}"`
    `git config alias.apache-merge "!git merge #{svn_branch}"`
    `git config alias.apache-pull  "!git apache-fetch && git apache-merge"`
    if svn_user
      `git config alias.apache-push  "!git-svn dcommit --username #{svn_user}"`
    else
      `git config alias.apache-push  "!git-svn dcommit"`
    end
    
    # Create github origin aliases
    `git config alias.get "!git apache-fetch && git fetch origin"`
    `git config alias.mrg "!git apache-merge && git merge origin"`
    `git config alias.put "!git apache-push && git push origin"`
    
    # This is Victor's cronjob
    `git config alias.synchronize "!git get && git mrg && git put"`
    
    # Final notices.
    puts <<-NOTICE + notice

    Your git repo #{local} has been configured, please review the 
       #{File.join(local, '.git/config')} file.

    NOTICE
  end  
end # perform method

main
