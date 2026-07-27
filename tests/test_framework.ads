--  Minimal zero-dependency assertion harness (no external test framework,
--  consistent with ada-FuSa's "stdlib only" runtime philosophy).

package Test_Framework is

   procedure Check (Condition : Boolean; Description : String);

   --  Prints a summary to stdout and returns True iff every Check so far
   --  passed. Call once, at the very end of the test run.
   function Report return Boolean;

end Test_Framework;
