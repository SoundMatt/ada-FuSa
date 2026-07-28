with Fusa.Fix;
with Test_Framework; use Test_Framework;

procedure Test_Fix is
begin
   --  fusa:test REQ-116
   Check (Fusa.Fix.Fix_Content
            ("procedure P is" & ASCII.LF & ASCII.HT & "null;" & ASCII.LF) =
          "procedure P is" & ASCII.LF & " null;" & ASCII.LF,
          "a tab character becomes a single space (ADA006)");

   Check (Fusa.Fix.Fix_Content ("begin  " & ASCII.LF & "   null;" & ASCII.LF) =
          "begin" & ASCII.LF & "   null;" & ASCII.LF,
          "trailing whitespace is stripped, leading indentation is preserved (LINT001)");

   Check (Fusa.Fix.Fix_Content
            ("a;" & ASCII.LF & ASCII.LF & ASCII.LF & ASCII.LF & "b;" & ASCII.LF) =
          "a;" & ASCII.LF & ASCII.LF & "b;" & ASCII.LF,
          "a run of 3+ consecutive blank lines collapses to exactly one (LINT002)");

   Check (Fusa.Fix.Fix_Content ("procedure P is begin null; end P;") =
          "procedure P is begin null; end P;" & ASCII.LF,
          "a missing trailing newline is added (LINT003)");

   Check (Fusa.Fix.Fix_Content
            ("procedure P is begin null; end P;" & ASCII.LF & ASCII.LF & ASCII.LF) =
          "procedure P is begin null; end P;" & ASCII.LF,
          "excess trailing newlines are removed down to exactly one, not "
          & "collapsed to a preserved blank line (LINT003)");

   declare
      Clean : constant String :=
        "procedure P is" & ASCII.LF & "begin" & ASCII.LF & "   null;" & ASCII.LF &
        "end P;" & ASCII.LF;
   begin
      Check (Fusa.Fix.Fix_Content (Clean) = Clean,
             "an already-clean file is returned unchanged");
   end;

   Check (Fusa.Fix.Fix_Content ("") = "", "an empty file fixes to empty, without crashing");
   Check (Fusa.Fix.Fix_Content (ASCII.LF & ASCII.LF & ASCII.LF) = "",
          "a file that is only blank lines fixes to empty");

   --  Idempotency is a safety property this command depends on: fixing
   --  already-fixed content must be a no-op, not a further change.
   declare
      Messy : constant String :=
        "procedure P is  " & ASCII.LF & ASCII.HT & ASCII.LF & ASCII.LF & ASCII.LF &
        "   null;" & ASCII.LF;
      Once  : constant String := Fusa.Fix.Fix_Content (Messy);
      Twice : constant String := Fusa.Fix.Fix_Content (Once);
   begin
      Check (Once = Twice, "Fix_Content is idempotent: fixing fixed content changes nothing");
   end;
end Test_Fix;
