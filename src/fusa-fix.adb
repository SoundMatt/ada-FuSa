with Ada.Strings.Fixed;
with Fusa.Files;

package body Fusa.Fix is

   --  Tabs -> single spaces, then trailing whitespace stripped. Leading
   --  whitespace (indentation) is never touched.
   function Clean_Line (Line : String) return String is
      Tab_Fixed : String (Line'Range);
   begin
      for I in Line'Range loop
         Tab_Fixed (I) := (if Line (I) = ASCII.HT then ' ' else Line (I));
      end loop;
      return Ada.Strings.Fixed.Trim (Tab_Fixed, Ada.Strings.Right);
   end Clean_Line;

   function Fix_Content (Content : String) return String is
      Raw_Lines : constant String_List := Fusa.Files.Split_Lines (Content);

      --  Pass 1: tab/trailing-whitespace cleanup on every line.
      Cleaned : String_List;
   begin
      for L of Raw_Lines loop
         Cleaned.Append (Clean_Line (L));
      end loop;

      --  Pass 2: drop trailing blank lines entirely (LINT003 wants
      --  exactly one terminating newline, not a preserved blank line).
      declare
         Last_Content : Natural := 0; --  0 = the whole file is blank
      begin
         for I in 1 .. Natural (Cleaned.Length) loop
            if Cleaned.Element (I)'Length > 0 then
               Last_Content := I;
            end if;
         end loop;

         if Last_Content = 0 then
            return ""; --  an all-blank (or empty) file fixes to empty
         end if;

         --  Pass 3: join, collapsing any interior run of 2+ consecutive
         --  blank lines down to exactly one (LINT002), through
         --  Last_Content only (trailing blanks beyond it are already
         --  excluded by this bound).
         declare
            Buf        : Unbounded_String := Null_Unbounded_String;
            Prev_Blank : Boolean := False;
         begin
            for I in 1 .. Last_Content loop
               declare
                  L : constant String := Cleaned.Element (I);
               begin
                  if L'Length = 0 then
                     if not Prev_Blank then
                        Append (Buf, ASCII.LF);
                     end if;
                     Prev_Blank := True;
                  else
                     Append (Buf, L & ASCII.LF);
                     Prev_Blank := False;
                  end if;
               end;
            end loop;
            return To_String (Buf);
         end;
      end;
   end Fix_Content;

end Fusa.Fix;
