with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces; use Interfaces;
with Fusa.Crc32;
with Fusa.Zip;
with Fusa.Files;
with Test_Framework; use Test_Framework;

procedure Test_Zip is
   Root : constant String := "tmp_test_zip";
begin
   --  Standard CRC-32 check value (ISO 3309 / ITU-T V.42 test vector).
   Check (Fusa.Crc32.Compute ("123456789") = 16#CBF4_3926#,
          "CRC-32 matches the standard '123456789' check value");
   Check (Fusa.Crc32.Compute ("") = 0, "CRC-32 of empty input is 0");

   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root);

   --  fusa:test REQ-020
   declare
      Entries : Fusa.Zip.Entry_List;
      Path    : constant String := Root & "/out.zip";
   begin
      Entries.Append
        (Fusa.Zip.Zip_Entry'(Name => To_Unbounded_String ("hello.txt"),
                              Data => To_Unbounded_String ("hello world")));
      Fusa.Zip.Write_Zip (Path, Entries);

      Check (Fusa.Files.Exists (Path), "Write_Zip creates the archive file");

      declare
         Content : constant String := Fusa.Files.Read_File (Path);
      begin
         Check (Content'Length > 4
                and then Character'Pos (Content (Content'First)) = 16#50#
                and then Character'Pos (Content (Content'First + 1)) = 16#4B#,
                "archive begins with the 'PK' local-file-header signature");
         Check (Content'Length >= 22
                and then Character'Pos (Content (Content'Last - 21)) = 16#50#
                and then Character'Pos (Content (Content'Last - 20)) = 16#4B#
                and then Character'Pos (Content (Content'Last - 19)) = 16#05#
                and then Character'Pos (Content (Content'Last - 18)) = 16#06#,
                "archive ends with the end-of-central-directory signature");
      end;
   end;

   --  Regression: the local file header's general-purpose flags field
   --  (bytes 6-7, little-endian) never set bit 11 (0x0800, "UTF-8
   --  filename") for a non-ASCII entry name, so strict readers could
   --  mis-decode it as the local codepage instead of UTF-8.
   declare
      Entries       : Fusa.Zip.Entry_List;
      Path          : constant String := Root & "/utf8.zip";
      Nonascii_Name : constant String :=
        "caf" & Character'Val (16#C3#) & Character'Val (16#A9#) & ".txt";
   begin
      Entries.Append
        (Fusa.Zip.Zip_Entry'(Name => To_Unbounded_String (Nonascii_Name),
                              Data => To_Unbounded_String ("x")));
      Fusa.Zip.Write_Zip (Path, Entries);
      declare
         Content : constant String := Fusa.Files.Read_File (Path);
      begin
         Check (Content'Length >= 8
                and then Character'Pos (Content (Content'First + 6)) = 16#00#
                and then Character'Pos (Content (Content'First + 7)) = 16#08#,
                "a non-ASCII entry name sets the UTF-8 filename flag "
                & "(bit 11) in the local file header");
      end;
   end;

   declare
      Entries : Fusa.Zip.Entry_List;
      Path    : constant String := Root & "/ascii.zip";
   begin
      Entries.Append
        (Fusa.Zip.Zip_Entry'(Name => To_Unbounded_String ("plain.txt"),
                              Data => To_Unbounded_String ("x")));
      Fusa.Zip.Write_Zip (Path, Entries);
      declare
         Content : constant String := Fusa.Files.Read_File (Path);
      begin
         Check (Content'Length >= 8
                and then Character'Pos (Content (Content'First + 6)) = 16#00#
                and then Character'Pos (Content (Content'First + 7)) = 16#00#,
                "an ASCII-only entry name leaves the flags field at 0");
      end;
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Zip;
