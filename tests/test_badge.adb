with Ada.Strings.Fixed;
with Fusa.Badge;
with Test_Framework; use Test_Framework;

procedure Test_Badge is
begin
   declare
      Svg : constant String := Fusa.Badge.Render_Svg ("fusa", "passing", "#4c1");
   begin
      --  fusa:test REQ-098
      Check (Ada.Strings.Fixed.Index (Svg, "<svg") = 1, "SVG document starts with <svg");
      Check (Ada.Strings.Fixed.Index (Svg, "</svg>") > 0, "SVG document is closed");
      Check (Ada.Strings.Fixed.Index (Svg, ">fusa<") > 0, "label text is present");
      Check (Ada.Strings.Fixed.Index (Svg, ">passing<") > 0, "message text is present");
      Check (Ada.Strings.Fixed.Index (Svg, "#4c1") > 0, "the requested colour is used");
   end;

   declare
      Svg : constant String := Fusa.Badge.Render_Svg ("a", "&<>""", "#e05d44");
   begin
      Check (Ada.Strings.Fixed.Index (Svg, "&amp;&lt;&gt;&quot;") > 0,
             "special XML characters in the message are escaped");
      Check (Ada.Strings.Fixed.Index (Svg, "&<>""") = 0,
             "the raw unescaped special characters do not appear literally in the SVG");
   end;

   declare
      Short : constant String := Fusa.Badge.Render_Svg ("x", "y", "#000");
      Long  : constant String :=
        Fusa.Badge.Render_Svg ("a much longer label", "a much longer message", "#000");
   begin
      Check (Short'Length < Long'Length,
             "a longer label/message produces a wider (larger) SVG document");
   end;
end Test_Badge;
