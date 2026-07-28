with Ada.Strings.Fixed;
with Fusa.Files;

package body Fusa.Func_Scan is

   function To_Upper (S : String) return String is
      Result : String (S'Range);
   begin
      for I in S'Range loop
         if S (I) in 'a' .. 'z' then
            Result (I) := Character'Val (Character'Pos (S (I)) - 32);
         else
            Result (I) := S (I);
         end if;
      end loop;
      return Result;
   end To_Upper;

   function Has_Suffix (S, Suffix : String) return Boolean is
     (S'Length >= Suffix'Length
      and then S (S'Last - Suffix'Length + 1 .. S'Last) = Suffix);

   function Starts_With (S, Prefix : String) return Boolean is
     (S'Length >= Prefix'Length
      and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);

   --  §1.4.1 targets a tool's own safety-relevant implementation, not test
   --  scaffolding -- a test helper's own .ads (e.g. a shared assertion
   --  library) is not "the tool's public API" in the sense the spec means,
   --  even though it is legitimately swept into the same Files list used
   --  for req/test annotation scanning (which MUST cover the test tree).
   --  "tests/" is a convention, not universal, but a reasonable default for
   --  a generic Ada project.
   function Is_Test_Path (Rel : String) return Boolean is
     (Starts_With (Rel, "tests/") or else Starts_With (Rel, "test/"));

   --  The declaration's name is not used by the --func-coverage gate itself
   --  (a percentage), but is kept for a future --gaps-style listing; a
   --  best-effort extraction (up to the first '(', ';', or whitespace) is
   --  enough for that purpose -- ';' matters for a parameterless
   --  declaration like "procedure Foo;", which has no space or '(' before
   --  the name ends.
   function Extract_Name (Decl_After_Keyword : String) return String is
      Trimmed : constant String :=
        Ada.Strings.Fixed.Trim (Decl_After_Keyword, Ada.Strings.Left);
   begin
      for I in Trimmed'Range loop
         if Trimmed (I) = ' ' or else Trimmed (I) = '('
           or else Trimmed (I) = ';'
         then
            return Trimmed (Trimmed'First .. I - 1);
         end if;
      end loop;
      return Trimmed;
   end Extract_Name;

   function Scan_Public_Functions
     (Project_Root : String; Files : String_List) return Func_List
   is
      Result : Func_List;
   begin
      for Rel of Files loop
         if Has_Suffix (Rel, ".ads") and then not Is_Test_Path (Rel) then
            declare
               Full : constant String := Fusa.Files.Join (Project_Root, Rel);
            begin
               if Fusa.Files.Exists (Full) then
                  declare
                     Content    : constant String := Fusa.Files.Read_File (Full);
                     Lines      : constant String_List := Fusa.Files.Split_Lines (Content);
                     In_Private : Boolean := False;
                  begin
                     for I in 1 .. Natural (Lines.Length) loop
                        declare
                           Trimmed : constant String :=
                             Ada.Strings.Fixed.Trim (Lines.Element (I), Ada.Strings.Both);
                           Upper   : constant String := To_Upper (Trimmed);
                        begin
                           if Upper = "PRIVATE" then
                              In_Private := True;
                           elsif not In_Private
                             and then (Starts_With (Upper, "FUNCTION ")
                                       or else Starts_With (Upper, "PROCEDURE "))
                           then
                              declare
                                 Kw_Len  : constant Positive :=
                                   (if Starts_With (Upper, "FUNCTION ") then 9 else 10);
                                 Name    : constant String :=
                                   Extract_Name
                                     (Trimmed (Trimmed'First + Kw_Len .. Trimmed'Last));
                                 Has_Tag : Boolean := False;
                              begin
                                 for J in reverse 1 .. I - 1 loop
                                    declare
                                       Prev : constant String :=
                                         Ada.Strings.Fixed.Trim
                                           (Lines.Element (J), Ada.Strings.Both);
                                    begin
                                       exit when not Starts_With (Prev, "--");
                                       if Ada.Strings.Fixed.Index (Prev, "fusa:req") > 0 then
                                          Has_Tag := True;
                                          exit;
                                       end if;
                                    end;
                                 end loop;

                                 Result.Append
                                   (Func_Info'
                                      (Name    => To_Unbounded_String (Name),
                                       File    => To_Unbounded_String (Rel),
                                       Line    => I,
                                       Has_Tag => Has_Tag));
                              end;
                           end if;
                        end;
                     end loop;
                  end;
               end if;
            end;
         end if;
      end loop;
      return Result;
   end Scan_Public_Functions;

end Fusa.Func_Scan;
