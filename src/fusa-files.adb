with Ada.Directories; use Ada.Directories;
with Ada.Streams.Stream_IO;
with Interfaces.C; use Interfaces.C;
with Interfaces.C.Strings;

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
      --  fusa:unsafe intentional error-boundary translation: any failure
      --  (Open/Read, or a bad Size read before Open) must still close the
      --  file handle if it was opened, then surface uniformly as
      --  Read_Error regardless of the underlying exception.
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

   procedure Write_File_Atomic (Path : String; Content : String) is
      --  Ada.Directories.Rename deliberately does NOT overwrite an
      --  existing destination (RM A.16.1 -- confirmed empirically:
      --  it raises Use_Error rather than replacing it), so it cannot be
      --  used for this. POSIX rename(2), imported directly here exactly
      --  like Make_Executable's chmod(2) import, DOES atomically replace
      --  an existing destination (including a symlink entry itself, not
      --  whatever it points to), which is the actual property this
      --  procedure exists to provide.
      function C_Rename
        (Old_Path, New_Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int;
      pragma Import (C, C_Rename, "rename");

      Temp   : constant String := Path & ".fusa-fix-tmp";
      Result : Interfaces.C.int;
   begin
      Write_File (Temp, Content);
      declare
         Old_C : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Temp);
         New_C : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      begin
         Result := C_Rename (Old_C, New_C);
         Interfaces.C.Strings.Free (Old_C);
         Interfaces.C.Strings.Free (New_C);
      end;
      if Result /= 0 then
         raise Write_Error with "cannot atomically replace file: " & Path;
      end if;
   end Write_File_Atomic;

   --  Removes "." path segments (a bare "." segment, e.g. from "./src" or
   --  "src/./sub"), RESOLVES ".." segments by popping the preceding real
   --  segment (so "src/./sub" -> "src/sub" and "a/b/../c" -> "a/c"), and
   --  collapses repeated "/" separators. A ".." with nothing left to pop
   --  (i.e. one that would climb above Path's own starting point) is kept
   --  literally, matching ordinary lexical path-normalisation semantics
   --  (no filesystem access, so a symlink can still defeat this -- see
   --  Fusa.Source_Scan's separate root-boundary check for the actual
   --  security guarantee against a sourceDirs/exclude entry escaping the
   --  project root).
   --
   --  This is what makes Join's ".." resolution real rather than
   --  cosmetic: Join(Project_Root, "../outside") used to produce the
   --  literal string "Project_Root/../outside", which Relative_To's
   --  purely-lexical prefix check would then WRONGLY treat as "inside"
   --  Project_Root (the string does start with "Project_Root/"), stripping
   --  the prefix and returning "../outside" -- an escaped path silently
   --  presented as project-relative. Resolving ".." here, before any
   --  Relative_To call ever sees the string, removes that entire class of
   --  bug at the source.
   function Normalize_Dot_Segments (Path : String) return String is
      Segments      : String_List;
      I             : Positive;
      Leading_Slash : constant Boolean :=
        Path'Length > 0 and then Path (Path'First) = '/';
   begin
      if Path'Length = 0 then
         return Path;
      end if;
      I := (if Leading_Slash then Path'First + 1 else Path'First);
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
               if Seg = ".." then
                  if not Segments.Is_Empty
                    and then Segments.Element (Natural (Segments.Length)) /= ".."
                  then
                     Segments.Delete_Last;
                  elsif not Leading_Slash then
                     --  Nothing real to pop and this is a relative path:
                     --  keep the ".." (a rooted "/../.." has no parent
                     --  above "/" to climb to, so it is simply dropped).
                     Segments.Append (Seg);
                  end if;
               elsif Seg /= "." and then Seg'Length > 0 then
                  Segments.Append (Seg);
               end if;
            end;
            if I <= Path'Last then
               I := I + 1; --  skip the separating '/'
            end if;
         end;
      end loop;

      declare
         Buf : Unbounded_String := Null_Unbounded_String;
      begin
         if Leading_Slash then
            Append (Buf, '/');
         end if;
         for J in 1 .. Natural (Segments.Length) loop
            if J > 1 then
               Append (Buf, '/');
            end if;
            Append (Buf, Segments.Element (J));
         end loop;
         return To_String (Buf);
      end;
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

   function Is_Within (Root, Path : String) return Boolean is
      --  Regression (fusa#96): Root must be run through the same
      --  Normalize_Dot_Segments pass that Join already applies to its
      --  result, or every relative Root that is exactly "." (Dir_Of's
      --  own default, and the single most common real-world invocation:
      --  no --dir at all) normalises to the empty string while Join(".",
      --  X) produces the bare, un-prefixed "X" -- so the raw-string
      --  comparison below would find no common prefix and wrongly report
      --  every in-tree Path as outside Root.
      Norm_Root   : constant String := Normalize_Dot_Segments (Root);
      Is_Absolute : constant Boolean :=
        Path'Length > 0 and then Path (Path'First) = '/';
      --  When Root normalises away entirely, Path itself is the only
      --  place an escape could still show up: Join's own
      --  Normalize_Dot_Segments leaves a leading ".." segment literal
      --  exactly when it ran out of real segments belonging to Root to
      --  pop (see that function's header comment) -- i.e. Name climbed
      --  above Root's own starting point.
      Escapes     : constant Boolean :=
        Path = ".."
        or else (Path'Length >= 3
                 and then Path (Path'First .. Path'First + 2) = "../");
   begin
      if Norm_Root'Length = 0 then
         return not Is_Absolute and then not Escapes;
      end if;
      declare
         Root_Len : constant Natural := Norm_Root'Length;
      begin
         return Path = Norm_Root
           or else (Path'Length > Root_Len
                    and then Path (Path'First .. Path'First + Root_Len - 1) =
                             Norm_Root
                    and then Path (Path'First + Root_Len) = '/');
      end;
   end Is_Within;

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
