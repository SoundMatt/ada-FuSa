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

   Ada.Directories.Delete_Tree (Root);
end Test_Zip;
