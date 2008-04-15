require 'yaml'

local = Dir.pwd if File.directory?(File.join('.git', Dir.pwd))

local ||=  ARGV.shift || File.expand_path('buildr', File.dirname(__FILE__))

origin = ARGV.shift || 'git@github.com:vic/buildr.git'

svn_branch = "apache/trunk"

puts "Buildr official commit channel is Apache's svn repository, however some"
puts "developers may prefer to use git while working on several features and"
puts "merging other's changes. "
puts
puts "This script will configure a buildr-git copy on so you can commit to svn."
puts "Local git copy: #{local}"
puts
puts "Press RETURN to continue or anything else to abort"
print "> "
unless gets.chomp.empty?
  puts "Aborting."
  exit(0)
end

`git clone #{origin} #{local} 1>&2` unless File.directory?(File.join('.git', origin))

Dir.chdir(local) do
  
  # Load the list of git-svn committers
  svn_authors_file = File.expand_path('etc/git-svn-authors', local)
  svn_authors = File.read(svn_authors_file)
  svn_authors.gsub!(/\s+=\s+/, ': ')
  svn_authors = YAML.load(svn_authors)

  # set the git-svn-authors file

  `git config svn.authorsfile "#{svn_authors_file}"`

  # Check that git is configured for the git developer
  email = `git config --get user.email`.chomp
  if email.empty?
    puts "Enter your email as listed on #{svn_authors_file}"
    print "> "
    email = gets.chomp
  end

  # Check user lis listed
  svn_user, git_contact = *svn_authors.find { |entry| /#{email}/i === entry.join(' ') }
  fail "You need to be a buildr commmitter listed on #{svn_authors_file}"+
    "\nPerhaps you need to set user.email, user.name on .git/config" unless git_contact
  if /\s*(.*?)\s+\<(.+)\>\s*/ === git_contact
    user_name, user_email = $1, $2
  else
    fail "Invalid contact string for #{svn_user}: #{git_contact.inspect}"
  end
  # Configure user name and email for git sake (and github's gravatar)
  puts "You claim to be #{user_name} <#{user_email}> with apache-svn user: #{svn_user}"
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
  `git config alias.apache-push  "!git-svn dcommit --username #{svn_user}"`

  # Create github origin aliases
  `git config alias.get "!git apache-fetch && git fetch origin"`
  `git config alias.mrg "!git apache-merge && git merge origin"`
  `git config alias.put "!git apache-push && git push origin"`

  # This is Victor's cronjob
  `git config alias.synchronize "!git get && git mrg && git put"`

  # Final notices.
  notice = <<-NOTICE
  Your git repo #{local} has been configured, please review the .git/config file.
  
  ALIASES:

  Some git aliases have been created for developer's convenience:

    git apache-fetch    # get changes from apache/trunk without merging them
                        # you can inspect what's happening on trunk without
                        # having to worry about merging conflicts.
                        # Inspect the remote branch with `git log apache/trunk`
                        # Or if you have a git-ui like `tig` you can use that.

    git apache-merge    # Merge already fetched changes on the current branch
                        # Use this command to get up to date with trunk changes
                        # you can always cherry-pick from the apache/trunk branch.

    git apache-pull     # get apache-fetch && git apache-merge
   
    git apache-push     # Push to Apache's SVN. Only staged changed (commited patches)
                        # will be sent to SVN. You need not to be on the master branch.
                        # Actually you can work on a tiny-feature branch and commit
                        # directly from it. 
                        #
                        # VERY IMPORTANT: 
                        # Missing commits on Apache's SVN will be sent using
                        # your #{svn_user} svn account. This means that you can make
                        # some commits on behalf of others (like user-contributed patches 
                        # from JIRA). Review the .git/config if you want to change login-name.
                        # 
                        #  See the recommended workflow to avoid commiting other developers' changes,
                        #  and the notes on github mirror.

   THE GITHUB MIRROR:

   Buildr has an unofficial git mirror on github, maintained by Victor: http://github.com/vic/buildr
   Actually it's not Victor who manually updates it, he has a cron-job on his server, that only runs
     git synchronize 
   A command you also have configured on your .git/config file.

   However there are some limitations due that git-svn cannot commit as multiple authors (unless all
   of them provided their passwords to Victor, yet he doesn't want to take over the world.)
   This means that if a commit "A" is pushed to vic/buildr/master and has not already been pushed
   by #{svn_user} using `git apache-push` your change will be commited to apache/trunk having Victor as the
   author (that's how he gains meritocratic points on Apache :P). 

   So, it's very important - if you care about meritocracy - to follow or at least that you get an
   idea of the recommended workflow.

   RECOMMENDED WORKFLOW:
   
   So now that you have your local buildr copy you can create topic branches to work on 
   independent features, and still merge easily with head changes. 

   They may seem lots of things to consider, but it's all for Buildr's healt. As all things git,
   you can always follow your own workflow and even create aliases on you .git/config file to 
   avoid typing much. So, here here they are:

   1) get your buildr-git configured (you have already do so, this was the most difficult part)

   2) create a topic branch to work on, say.. you want to add cool-feature:

        git checkout -b cool-feature master 
        # now on branch cool-feature

   3) hack hack hack.. use the source luke.
      every time you feel you have something important (added failing spec, added part of feature)
      you can commit your changes. If you want to be selective, use: git commit --interactive

   3) review your changes, get ALL specs passing, repeat step 3 as needed

   4) let's see what are they doing on trunk

        git apache-fetch
        # You can inspect the upstream changes without having to merge them
        git log apache/trunk # what are they doing!!
      
   5) integrate mainstream changes to your cool-feature branch (you can always use cherry-pick)

        git merge apache/trunk cool-feature
   
   6) Go to 3 unless ALL specs are passing.
   
   7) Now you have everyhing on stage area (git commit) and merged important changes from 
      apache/trunk. It's time to commit them to Apache's SVN. 

        git apache-push 

   8) (Optional) 
      Now your changes are on Apache SVN, you can wait for them to get synched to vic/buildr/master
      or push them yourself. You need Victor to add you as member, just ask for it.

        git fetch origin
        git rebase --into origin/master  master
        git push origin master:master

   9) Pull changes from origin frequently.
        
        git fetch origin
        git rebase --onto origin/master master master

   10) Unconditionally, Go to step 2 ;)  or share your buildr-git workflow, tips, etc.

  NOTICE
  
  puts notice

end
