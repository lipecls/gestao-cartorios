// Configuração do app. A chave "anon" do Supabase é pública por natureza:
// a proteção dos dados vem das regras (RLS) do arquivo supabase/schema.sql.
window.APP_CONFIG = {
  SUPABASE_URL: '',          // ex.: 'https://abcdefgh.supabase.co'
  SUPABASE_ANON_KEY: '',     // Project Settings → API → anon public
  IA_HABILITADA: false       // true depois de publicar a função gerar-minuta
};
