with Ada.Directories; use Ada.Directories;
with Ada.Streams.Stream_IO;

package body Fusa.Files is

   function Exists (Path : String) return Boolean is
     (Ada.Directories.Exists (Path));

   function Is_Directory (Path : String) return Boolean is
     (Ada.Directories.Exists (Path)
      and then Ada.Directories.Kind (Path) = Directory);

   function Read_File (Path : String) return String is
      use Ada.Streams.Stream_IO;
      File : File_Type;
      Size : constant Natural := Natural (Ada.Directories.Size (Path));
      Buf  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Size));
      Last : Ada.Streams.Stream_Element_Offset;
      Result : String (1 .. Size);
   begin
      Open (File, In_File, Path);
      Read (File, Buf, Last);
      Close (File);
      for I in 1 .. Natural (Last) loop
         Result (I) :=
           Character'Val (Buf (Ada.Streams.Stream_Element_Offset (I)));
      end loop;
      return Result (1 .. Natural (Last));
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         raise Read_Error with "cannot read file: " & Path;
   end Read_File;

   procedure Write_File (Path : String; Content : String) is
      use Ada.Streams.Stream_IO;
      File : File_Type;
      Buf  : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Content'Length));
   begin
      for I in Content'Range loop
         Buf (Ada.Streams.Stream_Element_Offset (I - Content'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Content (I)));
      end loop;
      Create (File, Out_File, Path);
      Write (File, Buf);
      Close (File);
   end Write_File;

   --  Removes "." path segments (a bare "." segment, e.g. from "./src" or
   --  "src/./sub") and collapses repeated "/" separators, so a sourceDirs
   --  entry like "./src" produces the same relative paths as plain "src"
   --  would, rather than leaking a literal "./" into every Loc.File value
   --  built from it.
   function Normalize_Dot_Segments (Path : String) return String is
      Result        : String (1 .. Path'Length);
      Out_Len       : Natural := 0;
      I             : Positive;
      Leading_Slash : constant Boolean :=
        Path'Length > 0 and then Path (Path'First) = '/';
   begin
      if Path'Length = 0 then
         return Path;
      end if;
      if Leading_Slash then
         Out_Len := 1;
         Result (1) := '/';
         I := Path'First + 1;
      else
         I := Path'First;
      end if;
      while I <= Path'Last loop
         declare
            Seg_Start : constant Positive := I;
         begin
            while I <= Path'Last and then Path (I) /= '/' loop
               I := I + 1;
            end loop;
            declare
               Seg : constant String := Path (Seg_Start .. I - 1);
            begin
               if Seg /= "." and then Seg'Length > 0 then
                  if Out_Len > 0 and then Result (Out_Len) /= '/' then
                     Out_Len := Out_Len + 1;
                     Result (Out_Len) := '/';
                  end if;
                  Result (Out_Len + 1 .. Out_Len + Seg'Length) := Seg;
                  Out_Len := Out_Len + Seg'Length;
               end if;
            end;
            if I <= Path'Last then
               I := I + 1; --  skip the separating '/'
            end if;
         end;
      end loop;
      return Result (1 .. Out_Len);
   end Normalize_Dot_Segments;

   function Join (Dir, Name : String) return String is
      Raw : constant String :=
        (if Dir'Length = 0 then Name
         elsif Dir (Dir'Last) = '/' then Dir & Name
         else Dir & "/" & Name);
   begin
      return Normalize_Dot_Segments (Raw);
   end Join;

   function Relative_To (Root, Path : String) return String is
   begin
      --  A prefix match alone is not enough: Root="/foo/bar" must not be
      --  treated as a prefix of the unrelated sibling Path="/foo/barbaz/x"
      --  just because the characters happen to match -- the character
      --  immediately after the matched prefix must be a path separator.
      if Path'Length > Root'Length
        and then Path (Path'First .. Path'First + Root'Length - 1) = Root
        and then Path (Path'First + Root'Length) = '/'
      then
         return Path (Path'First + Root'Length + 1 .. Path'Last);
      end if;
      return Path;
   end Relative_To;

   function Split_Lines (Content : String) return String_List is
      Result     : String_List;
      Line_Start : Integer := Content'First;
   begin
      for I in Content'First .. Content'Last loop
         if Content (I) = ASCII.LF then
            declare
               Line_End : Integer := I - 1;
            begin
               if Line_End >= Line_Start and then Content (Line_End) = ASCII.CR then
                  Line_End := Line_End - 1;
               end if;
               Result.Append (Content (Line_Start .. Line_End));
            end;
            Line_Start := I + 1;
         end if;
      end loop;
      if Line_Start <= Content'Last then
         Result.Append (Content (Line_Start .. Content'Last));
      end if;
      return Result;
   end Split_Lines;

end Fusa.Files;
