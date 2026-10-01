from pathlib import Path
import json,re,unittest,zipfile
from html.parser import HTMLParser
ROOT=Path(__file__).resolve().parents[1]
class HTML(HTMLParser):
 def __init__(self): super().__init__();self.ids=[];self.assets=[];self.scripts=[]
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  if 'id' in a:self.ids.append(a['id'])
  if tag=='script':self.scripts.append(a.get('src','INLINE'))
  for k in ['src','href']:
   v=a.get(k,'')
   if v.startswith('assets/') or v in ['script.js','style.css','upgrade.js','register-sw.js']:self.assets.append(v)
class Checks(unittest.TestCase):
 def test_json(self):
  for f in ['package.json','package-lock.json','vercel.json','manifest.webmanifest','docs/original-file-inventory.json']:json.loads((ROOT/f).read_text())
 def test_html_assets_and_ids(self):
  h=HTML();h.feed((ROOT/'index.html').read_text());self.assertEqual(len(h.ids),len(set(h.ids)))
  for v in h.assets:self.assertTrue((ROOT/v).is_file(),v)
  self.assertNotIn('INLINE',h.scripts)
 def test_no_client_privileges(self):
  s=(ROOT/'script.js').read_text()+(ROOT/'upgrade.js').read_text()
  for term in ['localStorage','SERVICE_ROLE_KEY','password_hash','x.pass===pass']:self.assertNotIn(term,s)
 def test_environment_empty(self):
  for line in (ROOT/'.env.example').read_text().splitlines():
   if line and not line.startswith('#'):self.assertIn(line.split('=')[0],['SUPABASE_URL','SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE_KEY','SITE_URL','NODE_ENV','PORT'])
 def test_rls_coverage(self):
  sql=(ROOT/'supabase/migrations/001_marketplace_initial.sql').read_text()
  for table in ['admins','profiles','listings','listing_images','listing_videos','favorites','messages','notifications','reports','banners','site_content','user_settings','audit_logs']:
   self.assertIn("'"+table+"'",sql);self.assertIn('create table public.'+table,sql)
  self.assertIn('where user_id=new.user_id and used=false',sql);self.assertIn('new.featured:=old.featured',sql)
 def test_no_credentials(self):
  for f in ROOT.rglob('*'):
   if f.is_file() and f.suffix not in ['.png','.jpg','.zip']:
    s=f.read_text();self.assertIsNone(re.search(r'eyJ[A-Za-z0-9_-]{25,}\.[A-Za-z0-9_-]{20,}\.',s),str(f));self.assertIsNone(re.search(r'sb_secret_[A-Za-z0-9]{12,}',s),str(f))
 def test_no_api_cache(self):
  s=(ROOT/'sw.js').read_text();self.assertNotIn('c.put',s);self.assertIn('caches.delete',s)
if __name__=='__main__':unittest.main(verbosity=2)
