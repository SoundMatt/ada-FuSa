with Interfaces; use Interfaces;
with Fusa.Crc32;
with Fusa.Files;

package body Fusa.Zip is

   procedure Put_U16 (Buf : in out Unbounded_String; V : Unsigned_16) is
   begin
      Append (Buf, Character'Val (Natural (V and 16#FF#)));
      Append (Buf, Character'Val (Natural (Shift_Right (V, 8) and 16#FF#)));
   end Put_U16;

   procedure Put_U32 (Buf : in out Unbounded_String; V : Unsigned_32) is
   begin
      for I in 0 .. 3 loop
         Append
           (Buf,
            Character'Val (Natural (Shift_Right (V, I * 8) and 16#FF#)));
      end loop;
   end Put_U32;

   --  True if Name contains any byte >= 0x80 (a UTF-8 multi-byte sequence,
   --  per this codebase's "Character = one raw byte" convention).
   function Has_Non_Ascii (Name : String) return Boolean is
   begin
      for C of Name loop
         if Character'Pos (C) >= 16#80# then
            return True;
         end if;
      end loop;
      return False;
   end Has_Non_Ascii;

   --  PKZIP APPNOTE general-purpose bit 11 ("Language encoding flag /
   --  EFS"): tells readers the filename is UTF-8, not the local codepage.
   function Zip_Flags (Name : String) return Unsigned_16 is
     (if Has_Non_Ascii (Name) then 16#0800# else 0);

   procedure Write_Zip (Path : String; Entries : Entry_List) is
      Buf     : Unbounded_String := Null_Unbounded_String;
      Count   : constant Natural := Natural (Entries.Length);
      Offsets : array (1 .. Count) of Unsigned_32;
      Crcs    : array (1 .. Count) of Unsigned_32;
      Idx     : Positive := 1;
   begin
      --  Local file headers + data.
      for E of Entries loop
         Offsets (Idx) := Unsigned_32 (Length (Buf));
         declare
            Name : constant String := To_String (E.Name);
            Data : constant String := To_String (E.Data);
            Crc  : constant Unsigned_32 := Fusa.Crc32.Compute (Data);
         begin
            Crcs (Idx) := Crc;
            Put_U32 (Buf, 16#0403_4b50#);              --  local file header sig
            Put_U16 (Buf, 20);                          --  version needed
            Put_U16 (Buf, Zip_Flags (Name));             --  flags
            Put_U16 (Buf, 0);                            --  method: stored
            Put_U16 (Buf, 0);                            --  mod time
            Put_U16 (Buf, 16#21#);                       --  mod date (1980-01-01)
            Put_U32 (Buf, Crc);
            Put_U32 (Buf, Unsigned_32 (Data'Length));    --  compressed size
            Put_U32 (Buf, Unsigned_32 (Data'Length));    --  uncompressed size
            Put_U16 (Buf, Unsigned_16 (Name'Length));
            Put_U16 (Buf, 0);                            --  extra length
            Append (Buf, Name);
            Append (Buf, Data);
         end;
         Idx := Idx + 1;
      end loop;

      declare
         Cd_Start : constant Unsigned_32 := Unsigned_32 (Length (Buf));
      begin
         Idx := 1;
         for E of Entries loop
            declare
               Name : constant String := To_String (E.Name);
            begin
               Put_U32 (Buf, 16#0201_4b50#);            --  central dir header sig
               Put_U16 (Buf, 20);                        --  version made by
               Put_U16 (Buf, 20);                        --  version needed
               Put_U16 (Buf, Zip_Flags (Name));           --  flags
               Put_U16 (Buf, 0);                          --  method: stored
               Put_U16 (Buf, 0);                          --  mod time
               Put_U16 (Buf, 16#21#);                     --  mod date
               Put_U32 (Buf, Crcs (Idx));
               Put_U32 (Buf, Unsigned_32 (Length (E.Data)));
               Put_U32 (Buf, Unsigned_32 (Length (E.Data)));
               Put_U16 (Buf, Unsigned_16 (Name'Length));
               Put_U16 (Buf, 0);                          --  extra length
               Put_U16 (Buf, 0);                          --  comment length
               Put_U16 (Buf, 0);                          --  disk number start
               Put_U16 (Buf, 0);                          --  internal attrs
               Put_U32 (Buf, 0);                          --  external attrs
               Put_U32 (Buf, Offsets (Idx));
               Append (Buf, Name);
            end;
            Idx := Idx + 1;
         end loop;

         declare
            Cd_Size : constant Unsigned_32 :=
              Unsigned_32 (Length (Buf)) - Cd_Start;
         begin
            Put_U32 (Buf, 16#0605_4b50#);                --  end of central dir sig
            Put_U16 (Buf, 0);                              --  disk number
            Put_U16 (Buf, 0);                              --  disk with cd
            Put_U16 (Buf, Unsigned_16 (Count));            --  entries this disk
            Put_U16 (Buf, Unsigned_16 (Count));            --  total entries
            Put_U32 (Buf, Cd_Size);
            Put_U32 (Buf, Cd_Start);
            Put_U16 (Buf, 0);                              --  comment length
         end;
      end;

      Fusa.Files.Write_File (Path, To_String (Buf));
   end Write_Zip;

end Fusa.Zip;
