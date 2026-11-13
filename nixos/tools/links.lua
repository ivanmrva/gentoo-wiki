-- Rewrite links between chapter files into in-document anchors for the single PDF.
--   03-system-modules.md#b8-modulespowernix  ->  #b8-modulespowernix
--   07-installation.md                       ->  #file-07-installation
-- Links to the web are left alone. Links into another guide (../...) have no target
-- inside this PDF, so they become plain text.
function Link(el)
  local t = el.target
  if t:match('^%a[%w+.-]*:') or t:match('^#') then return nil end
  if t:match('^%.%./') then return el.content end
  local file, frag = t:match('^([^#/]+)%.md#(.+)$')
  if file then el.target = '#' .. frag; return el end
  file = t:match('^([^#/]+)%.md$')
  if file then el.target = '#file-' .. file; return el end
end
