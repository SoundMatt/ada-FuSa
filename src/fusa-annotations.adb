with Ada.Strings.Fixed;
with Fusa.Files;

package body Fusa.Annotations is

   function Starts_With (S, Prefix : String) return Boolean is
     (S'Length >= Prefix'Length
      and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);

   --  True if Rest contains a further whitespace-delimited token that
   --  itself looks like a requirement id (starts with "REQ-") -- i.e. a
   --  second id on the same line, which is malformed. Plain trailing
   --  descriptive text (e.g. "REQ-AUTH-001 password must be validated")
   --  is not malformed.
   --  True if Token is plausibly an identifier (letters, digits, '-', '_',
   --  '.' only) rather than prose punctuation leaking in from a sentence
   --  that merely *mentions* the marker (e.g. a doc comment describing
   --  the annotation syntax itself, quoted with backticks/commas). Real
   --  requirement ids are always plain identifiers; anything else is
   --  treated as "this line isn't really an annotation" rather than a
   --  malformed one, so it's silently skipped instead of raising a
   --  spurious warning.
   function Is_Plausible_Token (Token : String) return Boolean is
   begin
      for C of Token loop
         if not (C in 'A' .. 'Z' or else C in 'a' .. 'z' or else C in '0' .. '9'
                 or else C = '-' or else C = '_' or else C = '.')
         then
            return False;
         end if;
      end loop;
      return True;
   end Is_Plausible_Token;

   function Has_Second_Req_Token (Rest : String) return Boolean is
      Idx : Integer := Rest'First;
   begin
      while Idx <= Rest'Last loop
         while Idx <= Rest'Last
           and then (Rest (Idx) = ' ' or else Rest (Idx) = ASCII.HT)
         loop
            Idx := Idx + 1;
         end loop;
         exit when Idx > Rest'Last;
         declare
            Start : constant Integer := Idx;
         begin
            while Idx <= Rest'Last
              and then Rest (Idx) /= ' ' and then Rest (Idx) /= ASCII.HT
            loop
               Idx := Idx + 1;
            end loop;
            if Starts_With (Rest (Start .. Idx - 1), "REQ-") then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Has_Second_Req_Token;

   --  Approximate "is Pos inside a string literal" check: counts
   --  double-quote characters before Pos on the line. An odd count means
   --  Pos falls inside an (unterminated-so-far) quoted region -- this
   --  doesn't handle Ada's doubled-quote ("") escape inside a string
   --  literal, but is enough to avoid treating example annotation text
   --  embedded in a string literal (e.g. a test fixture, or a Put_Line
   --  argument) as a real annotation.
   function In_String_Literal (Line : String; Pos : Positive) return Boolean is
      Quote_Count : Natural := 0;
   begin
      for I in Line'First .. Pos - 1 loop
         if Line (I) = '"' then
            Quote_Count := Quote_Count + 1;
         end if;
      end loop;
      return Quote_Count mod 2 = 1;
   end In_String_Literal;

   procedure Process_Marker
     (Line     : String;
      Marker   : String;
      Kind     : Tag_Kind;
      Rel      : String;
      Line_No  : Positive;
      Tags     : in out Tag_List;
      Findings : in out Finding_List)
   is
      Pos : constant Natural := Ada.Strings.Fixed.Index (Line, Marker);
   begin
      if Pos = 0 or else In_String_Literal (Line, Pos) then
         return;
      end if;

      declare
         After : constant String :=
           Ada.Strings.Fixed.Trim
             (Line (Pos + Marker'Length .. Line'Last), Ada.Strings.Left);
         Sp    : Natural := 0;
      begin
         for I in After'Range loop
            if After (I) = ' ' or else After (I) = ASCII.HT then
               Sp := I;
               exit;
            end if;
         end loop;

         declare
            Token : constant String :=
              (if Sp = 0 then After else After (After'First .. Sp - 1));
            Rest  : constant String :=
              (if Sp = 0 then "" else
                 Ada.Strings.Fixed.Trim (After (Sp .. After'Last), Ada.Strings.Left));
         begin
            if Token'Length = 0 then
               Findings.Append
                 (Make_Finding
                    (Rule_Id     => "TRACE001",
                     Severity    => Warning,
                     Message     =>
                       "malformed " & Marker & " annotation: missing requirement id",
                     Loc         => Make_Location (Rel, Line_No),
                     Category    => Fusa.Requirement,
                     Remediation => "add exactly one requirement id after " & Marker));
            elsif not Is_Plausible_Token (Token) then
               null;  --  prose mentioning the marker, not a real annotation
            elsif Has_Second_Req_Token (Rest) then
               Findings.Append
                 (Make_Finding
                    (Rule_Id     => "TRACE001",
                     Severity    => Warning,
                     Message     =>
                       "malformed " & Marker &
                       " annotation: more than one requirement id on the line",
                     Loc         => Make_Location (Rel, Line_No),
                     Category    => Fusa.Requirement,
                     Remediation =>
                       "keep exactly one requirement id per " & Marker & " annotation"));
            else
               Tags.Append
                 (Tag'(Requirement_Id => To_Unbounded_String (Token),
                       File           => To_Unbounded_String (Rel),
                       Line           => Line_No,
                       Kind           => Kind));
            end if;
         end;
      end;
   end Process_Marker;

   function Scan
     (Project_Root : String;
      Files        : String_List;
      Findings     : in out Finding_List) return Tag_List
   is
      Result : Tag_List;
   begin
      for Rel of Files loop
         declare
            Full : constant String := Fusa.Files.Join (Project_Root, Rel);
         begin
            if Fusa.Files.Exists (Full) then
               declare
                  Content : constant String := Fusa.Files.Read_File (Full);
                  Lines   : constant String_List := Fusa.Files.Split_Lines (Content);
                  Line_No : Positive := 1;
               begin
                  for Line of Lines loop
                     Process_Marker
                       (Line, "fusa:sec-test", Sec_Test, Rel, Line_No, Result, Findings);
                     Process_Marker
                       (Line, "fusa:test", Test, Rel, Line_No, Result, Findings);
                     Process_Marker
                       (Line, "fusa:req", Impl, Rel, Line_No, Result, Findings);
                     Line_No := Line_No + 1;
                  end loop;
               end;
            end if;
         end;
      end loop;
      return Result;
   end Scan;

end Fusa.Annotations;
