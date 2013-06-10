SET SCALA_HOME=F:\hudson\tools\scala-2.9.0.1
SET JRUBY_OPTS=-J-XX:MaxPermSize=312m -J-Xmx1024M
SET JAVA_OPTS=-Xmx1024m -XX:MaxPermSize=312m

IF "X%BUILD_RVM%" == "X1.9.3" SET RUBY_HOME=F:\hudson\tools\Ruby193-p194
IF "X%BUILD_RVM%" == "X1.9.2" SET RUBY_HOME=F:\hudson\tools\Ruby192-p290
IF "X%BUILD_RVM%" == "X1.8.7" SET RUBY_HOME=F:\hudson\tools\Ruby187-p370
IF "X%BUILD_RVM%" == "Xjruby" SET RUBY_HOME=F:\hudson\tools\jruby-1.6.7

IF "X%BUILD_JVM%" == "X1.5" SET JAVA_HOME=F:\hudson\tools\java\jdk1.5.0_22-64
IF "X%BUILD_JVM%" == "X1.6" SET JAVA_HOME=F:\hudson\tools\java\jdk1.6.0_27-64
IF "X%BUILD_JVM%" == "X1.7" SET JAVA_HOME=F:\hudson\tools\java\jdk1.7.0

SET PATH=%JAVA_HOME%\bin;%RUBY_HOME%\bin;%PATH%

CALL gem install bundler
CALL bundle update

SET BUILD_RAKE_TASK=ci
CALL rake clobber %BUILD_RAKE_TASK% --trace
