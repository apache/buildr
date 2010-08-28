
import junit.framework.TestCase;
import static junit.framework.Assert.assertEquals;

public class FooTest extends TestCase {
	
	public void testFoo() {
		Foo foo = new Foo();
		assertEquals("bar", foo.bar());
	}
	
}