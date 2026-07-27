with Fusa.Json; use Fusa.Json;
with Fusa.Json.Writer;
with Test_Framework; use Test_Framework;

procedure Test_Json is

   function Raises_Json_Error (Text : String) return Boolean is
   begin
      declare
         V : constant Fusa.Json.Value_Access := Fusa.Json.Parse (Text);
         pragma Unreferenced (V);
      begin
         return False;
      end;
   exception
      when Fusa.Json.Json_Error =>
         return True;
   end Raises_Json_Error;

begin
   --  Parser + accessors
   --  fusa:test REQ-018
   declare
      V : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse
          ("{""a"":1,""b"":""hi"",""c"":true,""d"":[1,2,3]," &
           """e"":{""f"":""nested""},""g"":null}");
   begin
      Check (Fusa.Json.Is_Object (V), "root parses as object");
      Check (Fusa.Json.Get_String (V, "b") = "hi", "string field reads back");
      Check (Fusa.Json.Get_Bool (V, "c") = True, "bool field reads back");
      Check (Fusa.Json.Array_Length (Fusa.Json.Get_Array (V, "d")) = 3,
             "array length is 3");
      Check (Fusa.Json.Get_String (Fusa.Json.Get_Member (V, "e"), "f") = "nested",
             "nested object field reads back");
      Check (Fusa.Json.Get_String (V, "missing", "def") = "def",
             "missing key returns supplied default");
      Check (not Fusa.Json.Has_Key (V, "missing"), "Has_Key false for absent key");
      Check (Fusa.Json.Has_Key (V, "a"), "Has_Key true for present key");
   end;

   --  Escapes and \u
   declare
      V : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""s"":""line1\nline2\t\""q\"" é""}");
   begin
      Check (Fusa.Json.Get_String (V, "s")'Length > 0, "escaped string parses");
   end;

   --  Malformed input raises Json_Error
   declare
      Raised : Boolean := False;
   begin
      begin
         declare
            V : constant Fusa.Json.Value_Access := Fusa.Json.Parse ("{""a"": }");
            pragma Unreferenced (V);
         begin
            null;
         end;
      exception
         when Fusa.Json.Json_Error =>
            Raised := True;
      end;
      Check (Raised, "malformed json raises Json_Error");
   end;

   --  Regression: malformed exponents used to crash with an unhandled
   --  CONSTRAINT_ERROR instead of raising Json_Error.
   Check (Raises_Json_Error ("{""n"":1e}"),
          "a bare exponent with no digits raises Json_Error");
   Check (Raises_Json_Error ("{""n"":1e+}"),
          "an exponent sign with no digits raises Json_Error");
   Check (not Raises_Json_Error ("{""n"":1e10}"), "a well-formed exponent still parses");
   Check (not Raises_Json_Error ("{""n"":1e+10}"),
          "a well-formed signed exponent still parses");

   --  Regression: RFC 8259 forbids a leading zero followed by another
   --  digit, and requires a digit after a decimal point.
   Check (Raises_Json_Error ("{""n"":01}"),
          "a leading zero followed by a digit raises Json_Error");
   Check (Raises_Json_Error ("{""n"":1.}"),
          "a bare trailing decimal point raises Json_Error");
   Check (not Raises_Json_Error ("{""n"":0}"), "a lone zero is still valid");
   Check (not Raises_Json_Error ("{""n"":0.5}"), "0.5 is still valid");
   Check (not Raises_Json_Error ("{""n"":-0.5}"), "-0.5 is still valid");

   --  Regression: unbounded recursion used to overflow the stack
   --  (STORAGE_ERROR) on deeply nested input instead of raising Json_Error.
   declare
      Deep : constant String := (1 .. 600 => '[') & (1 .. 600 => ']');
   begin
      Check (Raises_Json_Error (Deep),
             "excessive nesting depth raises Json_Error instead of crashing");
   end;
   declare
      Shallow : constant String := (1 .. 10 => '[') & (1 .. 10 => ']');
   begin
      Check (not Raises_Json_Error (Shallow), "ordinary nesting depth still parses fine");
   end;

   --  Regression: \u surrogate pairs were never combined, producing
   --  invalid (CESU-8-style) UTF-8 for non-BMP characters.
   declare
      --  U+1F600 (grinning face emoji) as a UTF-16 surrogate pair.
      V : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""s"":""\uD83D\uDE00""}");
      S : constant String := Fusa.Json.Get_String (V, "s");
   begin
      Check (S'Length = 4
             and then Character'Pos (S (S'First))     = 16#F0#
             and then Character'Pos (S (S'First + 1)) = 16#9F#
             and then Character'Pos (S (S'First + 2)) = 16#98#
             and then Character'Pos (S (S'First + 3)) = 16#80#,
             "a combined surrogate pair encodes to the correct 4-byte "
             & "UTF-8 sequence for U+1F600");
   end;
   Check (Raises_Json_Error ("{""s"":""\uD800""}"),
          "a lone unpaired high surrogate raises Json_Error");
   Check (Raises_Json_Error ("{""s"":""\uDC00""}"),
          "a lone unpaired low surrogate raises Json_Error");
   Check (Raises_Json_Error ("{""s"":""\uD800X""}"),
          "a high surrogate not followed by a \\u low surrogate raises Json_Error");

   --  Regression: duplicate object keys used to keep both members, with
   --  Get_Member resolving to the first (rather than last, as most JSON
   --  tooling does).
   declare
      V : constant Fusa.Json.Value_Access := Fusa.Json.Parse ("{""a"":1,""a"":2}");
      M : constant Fusa.Json.Value_Access := Fusa.Json.Get_Member (V, "a");
   begin
      Check (M /= null and then M.Kind = Fusa.Json.Json_Number
             and then M.Num_Val = 2.0,
             "a duplicate object key resolves to the last value, not the first");
   end;

   --  Writer: object/array/nesting/empty-object round trip
   declare
      W : Fusa.Json.Writer.Instance;
   begin
      W.Object_Start;
      W.Field ("x", "y");
      W.Key ("arr");
      W.Array_Start;
      W.Value ("a");
      W.Value ("b");
      W.Array_End;
      W.Key ("empty");
      W.Object_Start;
      W.Object_End;
      W.Object_End;

      declare
         Out_Text : constant String := Fusa.Json.Writer.To_String (W);
         Reparsed : constant Fusa.Json.Value_Access := Fusa.Json.Parse (Out_Text);
      begin
         Check (Fusa.Json.Get_String (Reparsed, "x") = "y",
                "writer output round-trips through the parser");
         Check (Fusa.Json.Array_Length (Fusa.Json.Get_Array (Reparsed, "arr")) = 2,
                "written array round-trips with correct length");
      end;
   end;

   --  Regression: protocol misuse used to either silently emit invalid
   --  JSON or crash with a raw CONSTRAINT_ERROR; it now raises the
   --  documented Writer_Error instead.
   declare
      W      : Fusa.Json.Writer.Instance;
      Raised : Boolean := False;
   begin
      begin
         W.Object_End;
      exception
         when Fusa.Json.Writer.Writer_Error =>
            Raised := True;
      end;
      Check (Raised, "Object_End with nothing open raises Writer_Error");
   end;

   declare
      W      : Fusa.Json.Writer.Instance;
      Raised : Boolean := False;
   begin
      W.Array_Start;
      begin
         W.Object_End;
      exception
         when Fusa.Json.Writer.Writer_Error =>
            Raised := True;
      end;
      Check (Raised,
             "Object_End raises Writer_Error when the innermost open "
             & "container is actually an array");
   end;

   declare
      W      : Fusa.Json.Writer.Instance;
      Raised : Boolean := False;
   begin
      W.Object_Start;
      W.Key ("a");
      begin
         W.Key ("b");
      exception
         when Fusa.Json.Writer.Writer_Error =>
            Raised := True;
      end;
      Check (Raised, "two Key() calls in a row raises Writer_Error");
   end;

   declare
      W      : Fusa.Json.Writer.Instance;
      Raised : Boolean := False;
   begin
      W.Object_Start;
      begin
         W.Value ("x");
      exception
         when Fusa.Json.Writer.Writer_Error =>
            Raised := True;
      end;
      Check (Raised,
             "a value written inside an object with no preceding Key() "
             & "raises Writer_Error");
   end;

   declare
      W      : Fusa.Json.Writer.Instance;
      Raised : Boolean := False;
   begin
      begin
         for I in 1 .. Fusa.Json.Writer.Max_Depth + 1 loop
            W.Array_Start;
         end loop;
      exception
         when Fusa.Json.Writer.Writer_Error =>
            Raised := True;
      end;
      Check (Raised, "nesting beyond Max_Depth raises Writer_Error");
   end;
end Test_Json;
