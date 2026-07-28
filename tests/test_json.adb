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
   --  fusa:test REQ-032
   --  fusa:test REQ-034
   --  fusa:test REQ-035
   --  fusa:test REQ-036
   declare
      V : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse
          ("{""a"":1,""b"":""hi"",""c"":true,""d"":[1,2,3],""h"":[""x"",""y""]," &
           """e"":{""f"":""nested""},""g"":null}");
   begin
      Check (Fusa.Json.Is_Object (V), "root parses as object");
      Check (Fusa.Json.Get_String (V, "b") = "hi", "string field reads back");
      Check (Fusa.Json.Get_Bool (V, "c") = True, "bool field reads back");
      Check (Fusa.Json.Array_Length (Fusa.Json.Get_Array (V, "d")) = 3,
             "array length is 3");
      Check (Fusa.Json.As_String (Fusa.Json.Array_Item (Fusa.Json.Get_Array (V, "h"), 1)) = "x",
             "Array_Item + As_String reads back the first element of a string array");
      Check (Fusa.Json.Get_String (Fusa.Json.Get_Member (V, "e"), "f") = "nested",
             "nested object field reads back");
      Check (Fusa.Json.Get_String (V, "missing", "def") = "def",
             "missing key returns supplied default");
      --  fusa:test REQ-033
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

   --  Regression: a syntactically well-formed number that overflows
   --  Long_Float's range (GNAT converts it to IEEE +/-Infinity rather
   --  than raising) used to be accepted silently, propagating a
   --  non-finite value into every downstream consumer with no error at
   --  the point of parsing.
   Check (Raises_Json_Error ("{""n"":1e400}"),
          "a number that overflows to +Infinity raises Json_Error");
   Check (Raises_Json_Error ("{""n"":-1e400}"),
          "a number that overflows to -Infinity raises Json_Error");
   Check (not Raises_Json_Error ("{""n"":1e300}"),
          "a large but in-range number still parses fine");

   --  Regression: RFC 8259 section 7 requires control characters
   --  (U+0000-U+001F) inside a string literal to be escaped; a literal
   --  one used to be accepted and copied straight into the result.
   Check (Raises_Json_Error ("{""s"":""a" & ASCII.LF & "b""}"),
          "a literal, unescaped newline inside a string raises Json_Error");
   Check (Raises_Json_Error ("{""s"":""a" & ASCII.HT & "b""}"),
          "a literal, unescaped tab inside a string raises Json_Error");
   Check (not Raises_Json_Error ("{""s"":""a\nb""}"),
          "a properly-escaped \\n still parses fine");

   --  Regression: duplicate-key handling used to rescan every
   --  previously-parsed member on each new key (O(n^2) on n keys);
   --  the hashed-map-backed version must still produce the same
   --  last-value-wins result across more than one duplicate.
   declare
      V : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""a"":1,""b"":2,""a"":3,""c"":4,""a"":5}");
   begin
      Check (Fusa.Json.Get_Member (V, "a").Num_Val = 5.0,
             "the last of three repeated keys wins");
      Check (Fusa.Json.Get_Member (V, "b").Num_Val = 2.0,
             "a key that was never duplicated is unaffected");
      Check (Fusa.Json.Get_Member (V, "c").Num_Val = 4.0,
             "a key duplicated after it, not before, is unaffected");
   end;

   --  Writer: object/array/nesting/empty-object round trip
   --  fusa:test REQ-025
   --  fusa:test REQ-026
   --  fusa:test REQ-027
   --  fusa:test REQ-029
   --  fusa:test REQ-031
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

   --  Value/Field's Integer and Boolean overloads, and Null_Value -- none
   --  of these are ever called from real command code (every production
   --  call site uses the String overloads or Field's typed shorthand for
   --  scalars, and no command emits a bare JSON null), so this is their
   --  only exercise.
   --  fusa:test REQ-027
   --  fusa:test REQ-028
   declare
      W : Fusa.Json.Writer.Instance;
   begin
      W.Object_Start;
      W.Key ("n");
      W.Value (42);
      W.Key ("b");
      W.Value (True);
      W.Key ("nothing");
      W.Null_Value;
      W.Key ("arr");
      W.Array_Start;
      W.Value (1);
      W.Value (False);
      W.Null_Value;
      W.Array_End;
      W.Object_End;

      declare
         Out_Text : constant String := Fusa.Json.Writer.To_String (W);
         Reparsed : constant Fusa.Json.Value_Access := Fusa.Json.Parse (Out_Text);
         Arr      : constant Fusa.Json.Value_Access := Fusa.Json.Get_Array (Reparsed, "arr");
      begin
         Check (Fusa.Json.Get_Bool (Reparsed, "b") = True, "Value(Boolean) round-trips");
         Check (Fusa.Json.Get_Member (Reparsed, "n").Kind = Fusa.Json.Json_Number
                and then Fusa.Json.Get_Member (Reparsed, "n").Num_Val = 42.0,
                "Value(Integer) round-trips as a JSON number");
         Check (Fusa.Json.Get_Member (Reparsed, "nothing").Kind = Fusa.Json.Json_Null,
                "Null_Value round-trips as a JSON null");
         Check (Fusa.Json.Array_Item (Arr, 3).Kind = Fusa.Json.Json_Null,
                "Null_Value also works as an array element, not just an object value");
      end;
   end;

   --  Field_If_Non_Blank: omitted when the value is blank, emitted
   --  otherwise -- never both, so a single object exercises both halves.
   --  fusa:test REQ-030
   declare
      W : Fusa.Json.Writer.Instance;
   begin
      W.Object_Start;
      W.Field_If_Non_Blank ("present", "value");
      W.Field_If_Non_Blank ("absent", "");
      W.Object_End;

      declare
         Out_Text : constant String := Fusa.Json.Writer.To_String (W);
         Reparsed : constant Fusa.Json.Value_Access := Fusa.Json.Parse (Out_Text);
      begin
         Check (Fusa.Json.Has_Key (Reparsed, "present"),
                "Field_If_Non_Blank emits the field when the value is non-empty");
         Check (not Fusa.Json.Has_Key (Reparsed, "absent"),
                "Field_If_Non_Blank omits the field entirely when the value is empty");
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
