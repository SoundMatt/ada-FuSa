with Fusa.Json;
with Fusa.Json.Writer;
with Test_Framework; use Test_Framework;

procedure Test_Json is
begin
   --  Parser + accessors
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
end Test_Json;
