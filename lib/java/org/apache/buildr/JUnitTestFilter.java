package org.apache.buildr;

import java.io.File;
import java.io.IOException;
import java.net.URL;
import java.net.URLClassLoader;
import java.net.MalformedURLException;
import java.util.Vector;

public class JUnitTestFilter {

  private ClassLoader _loader;

  public JUnitTestFilter(String[] paths) throws IOException {
    URL[] urls = new URL[paths.length];
    for (int i = 0 ; i < paths.length ; ++i) {
      File file = new File(paths[i]).getCanonicalFile();
      if (file.exists())
        urls[i] = file.toURL();
      else
        throw new IOException("No file or directory with the name " + file);
    }
    _loader = new URLClassLoader(urls, getClass().getClassLoader());
  }

  public String[] filter(String[] names) throws ClassNotFoundException {
    Vector testCases = new Vector();
    Class testCase = _loader.loadClass("junit.framework.TestCase");
    for (int i = 0 ; i < names.length ; ++i) {
      Class cls = _loader.loadClass(names[i]);
      if (testCase.isAssignableFrom(cls))
        testCases.add(names[i]);
    }
    String[] result = new String[testCases.size()];
    testCases.toArray(result);
    return result;
  }

}
