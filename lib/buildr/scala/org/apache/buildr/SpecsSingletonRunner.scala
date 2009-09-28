package org.apache.buildr

import java.net.{URL, URLClassLoader}
import java.io.File

/**
 * @author Daniel Spiewak
 */
object SpecsSingletonRunner {
  type Spec = { def main(args: Array[String]) }
  
  // Incompatible with JVM 1.4 target
  // @throws(classOf[Throwable])
  def main(args: Array[String]) {
    val (colors, spec) = if (args.length > 1 && args(1) == "-c")
      (true, args(2))
    else
      (false, args(1))
    
    run(args(0), colors, spec)
  }
  
  // Incompatible with JVM 1.4 target
  // @throws(classOf[Throwable])
  def run(path: String, colors: Boolean, spec: String) = {
    val parent = new File(path)
    val specURL = new File(parent, spec.replace('.', '/') + ".class").toURL
    val loader = new URLClassLoader(Array(specURL), getClass.getClassLoader)
    
    val clazz = loader.loadClass(spec)
    val instance = clazz.getField("MODULE$").get(null).asInstanceOf[Spec]
    
    instance.main(if (colors) Array("-c") else Array())
  }
}
