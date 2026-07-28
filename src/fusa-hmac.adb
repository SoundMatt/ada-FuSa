with Interfaces; use Interfaces;
with Fusa.Sha256;

package body Fusa.Hmac is

   Block_Size : constant := 64; --  SHA-256's block size in bytes.

   function Nibble (C : Character) return Unsigned_8 is
     (case C is
         when '0' .. '9' => Character'Pos (C) - Character'Pos ('0'),
         when 'a' .. 'f' => Character'Pos (C) - Character'Pos ('a') + 10,
         when 'A' .. 'F' => Character'Pos (C) - Character'Pos ('A') + 10,
         when others     => 0);

   --  Decodes a lowercase hex digest (as returned by Fusa.Sha256.Hex_Digest)
   --  back into its raw bytes, so it can be fed into a further SHA-256
   --  round as HMAC's nested construction requires.
   function Hex_To_Bytes (Hex : String) return String is
      Result : String (1 .. Hex'Length / 2);
   begin
      for I in Result'Range loop
         declare
            Hi : constant Unsigned_8 := Nibble (Hex (Hex'First + 2 * (I - 1)));
            Lo : constant Unsigned_8 := Nibble (Hex (Hex'First + 2 * (I - 1) + 1));
         begin
            Result (I) := Character'Val (Hi * 16 + Lo);
         end;
      end loop;
      return Result;
   end Hex_To_Bytes;

   function Sha256_Hex (Key, Message : String) return String is
      K : String (1 .. Block_Size) := (others => Character'Val (0));
   begin
      --  RFC 2104 sec.2: a key longer than the block size is first hashed
      --  down; a key shorter than the block size is zero-padded on the
      --  right (K above is already all-zero, so only the actual key bytes
      --  need to be written in).
      if Key'Length > Block_Size then
         declare
            Hashed : constant String := Hex_To_Bytes (Fusa.Sha256.Hex_Digest (Key));
         begin
            K (1 .. Hashed'Length) := Hashed;
         end;
      else
         K (1 .. Key'Length) := Key;
      end if;

      declare
         O_Pad, I_Pad : String (1 .. Block_Size);
      begin
         for I in 1 .. Block_Size loop
            O_Pad (I) := Character'Val (Natural (Unsigned_8 (Character'Pos (K (I))) xor 16#5c#));
            I_Pad (I) := Character'Val (Natural (Unsigned_8 (Character'Pos (K (I))) xor 16#36#));
         end loop;

         declare
            Inner_Bytes : constant String :=
              Hex_To_Bytes (Fusa.Sha256.Hex_Digest (I_Pad & Message));
         begin
            return Fusa.Sha256.Hex_Digest (O_Pad & Inner_Bytes);
         end;
      end;
   end Sha256_Hex;

   function Constant_Time_Equal (A, B : String) return Boolean is
      Max_Len  : constant Natural := Natural'Max (A'Length, B'Length);
      Mismatch : Boolean := A'Length /= B'Length;
   begin
      --  Always iterates the full Max_Len regardless of where (or
      --  whether) a mismatch occurs -- no early "exit", unlike a plain
      --  "=" comparison, which stops at the first differing character
      --  and so leaks how many leading characters matched via timing.
      for I in 0 .. Max_Len - 1 loop
         declare
            Ca : constant Character :=
              (if I < A'Length then A (A'First + I) else Character'Val (0));
            Cb : constant Character :=
              (if I < B'Length then B (B'First + I) else Character'Val (0));
         begin
            if Ca /= Cb then
               Mismatch := True;
            end if;
         end;
      end loop;
      return not Mismatch;
   end Constant_Time_Equal;

end Fusa.Hmac;
