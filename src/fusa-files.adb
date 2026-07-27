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

   function Join (Dir, Name : String) return String is
   begin
      if Dir'Length = 0 then
         return Name;
      elsif Dir (Dir'Last) = '/' then
         return Dir & Name;
      else
         return Dir & "/" & Name;
      end if;
   end Join;

   function Relative_To (Root, Path : String) return String is
   begin
      if Path'Length > Root'Length
        and then Path (Path'First .. Path'First + Root'Length - 1) = Root
      then
         declare
            Rest : constant String :=
              Path (Path'First + Root'Length .. Path'Last);
         begin
            if Rest'Length > 0 and then Rest (Rest'First) = '/' then
               return Rest (Rest'First + 1 .. Rest'Last);
            else
               return Rest;
            end if;
         end;
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
