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
   --  fusa:test REQ-055
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

   --  Regression: Write_Zip's central-directory offset bookkeeping
   --  (Offsets array indexed by entry position) was only ever exercised
   --  with single-entry archives, even though production usage always
   --  writes 5-8 entries -- an accumulation bug (e.g. using the wrong
   --  running total, or a name/data-length miscount) would silently
   --  corrupt every offset after the first without any test catching it.
   --  This walks the actual central directory and, for every entry,
   --  follows its recorded local-file-header offset and verifies a real
   --  local header with the matching name sits there -- proving the
   --  offsets are correct, not just that the file is non-empty.
   declare
      function Read_U16 (S : String; At_Pos : Positive) return Natural is
        (Character'Pos (S (At_Pos)) + Character'Pos (S (At_Pos + 1)) * 256);
      function Read_U32 (S : String; At_Pos : Positive) return Natural is
        (Character'Pos (S (At_Pos))
         + Character'Pos (S (At_Pos + 1)) * 256
         + Character'Pos (S (At_Pos + 2)) * 65536
         + Character'Pos (S (At_Pos + 3)) * 16_777_216);

      Entries : Fusa.Zip.Entry_List;
      Path    : constant String := Root & "/multi.zip";
      Names   : constant array (1 .. 6) of Unbounded_String :=
        (To_Unbounded_String ("a.json"), To_Unbounded_String ("bb/report.json"),
         To_Unbounded_String ("ccc.txt"), To_Unbounded_String ("d.md"),
         To_Unbounded_String ("eeeee-evidence.json"), To_Unbounded_String ("f.zip.manifest"));
      Datas   : constant array (1 .. 6) of Unbounded_String :=
        (To_Unbounded_String ("{}"), To_Unbounded_String ("a longer body of report content"),
         To_Unbounded_String ("x"), To_Unbounded_String ("# heading" & ASCII.LF & "text"),
         To_Unbounded_String ("evidence payload, somewhat longer than the others"),
         To_Unbounded_String (""));
   begin
      for I in Names'Range loop
         Entries.Append (Fusa.Zip.Zip_Entry'(Name => Names (I), Data => Datas (I)));
      end loop;
      Fusa.Zip.Write_Zip (Path, Entries);

      declare
         Content : constant String := Fusa.Files.Read_File (Path);
         --  The EOCD record is the fixed 22 bytes at the very end (none
         --  of these entries use a zip comment).
         Eocd    : constant Positive := Content'Last - 21;
         Total_Entries : constant Natural := Read_U16 (Content, Eocd + 10);
         Cd_Offset     : constant Natural := Read_U32 (Content, Eocd + 16);
         Cd_Pos        : Natural := Content'First + Cd_Offset;
         All_Verified  : Boolean := True;
      begin
         Check (Content (Eocd) = Character'Val (16#50#)
                and then Content (Eocd + 1) = Character'Val (16#4B#)
                and then Content (Eocd + 2) = Character'Val (16#05#)
                and then Content (Eocd + 3) = Character'Val (16#06#),
                "the end-of-central-directory record is where expected "
                & "(22 bytes before end of file, no comment)");
         Check (Total_Entries = 6,
                "the EOCD's total-entries field reflects all 6 written entries");

         for I in 1 .. Total_Entries loop
            --  Central directory fixed header is 46 bytes; name-length
            --  is at offset 28, local-header-offset at offset 42.
            declare
               Name_Len    : constant Natural := Read_U16 (Content, Cd_Pos + 28);
               Local_Off   : constant Natural := Read_U32 (Content, Cd_Pos + 42);
               Cd_Name     : constant String := Content (Cd_Pos + 46 .. Cd_Pos + 45 + Name_Len);
               Local_Pos   : constant Natural := Content'First + Local_Off;
               --  Local file header fixed portion is 30 bytes;
               --  name-length is at offset 26.
               Local_Name_Len : constant Natural := Read_U16 (Content, Local_Pos + 26);
               Local_Name     : constant String :=
                 Content (Local_Pos + 30 .. Local_Pos + 29 + Local_Name_Len);
            begin
               if Content (Local_Pos) /= Character'Val (16#50#)
                 or else Content (Local_Pos + 1) /= Character'Val (16#4B#)
                 or else Content (Local_Pos + 2) /= Character'Val (16#03#)
                 or else Content (Local_Pos + 3) /= Character'Val (16#04#)
                 or else Local_Name /= Cd_Name
               then
                  All_Verified := False;
               end if;
               Cd_Pos := Cd_Pos + 46 + Name_Len;
            end;
         end loop;
         Check (All_Verified,
                "every one of the 6 entries' central-directory "
                & "local-header-offset actually points to a local file "
                & "header whose name matches -- proving the offset "
                & "bookkeeping accumulates correctly across multiple "
                & "entries, not just the first");
      end;
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Zip;
