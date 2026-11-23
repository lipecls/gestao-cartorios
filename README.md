# Gestão de Cartórios

App de gestão (PWA) para assessoria de serventias extrajudiciais. Atende vários cartórios clientes, e cada um vê só os seus dados.

**Módulos:** Início (pendências e visão geral) · Financeiro (plano de contas COBJUD, regime de caixa) · RH (ASO, férias, avaliação, pasta funcional) · PQTA 2026 (59 itens, pontuação estimada) · Prestação de contas (balancete COBJUD/FERMOJUPI, checklist e prazo do dia 15) · Minutas de atos (pedido → elaboração → revisão → entrega).

**Tecnologia:** HTML/JS sem etapa de build + [Supabase](https://supabase.com) (Postgres, login e tempo real). É instalável no celular e abre sem internet em modo somente leitura.

---

## Como colocar no ar

### 1. Criar o banco no Supabase
1. Crie um projeto em supabase.com. O plano gratuito serve para começar; escolha a região São Paulo.
2. Abra **SQL Editor**, cole o conteúdo de `supabase/schema.sql` e rode.
3. Em **Authentication → Providers → Email**, desative "Allow new users to sign up". Assim só entra quem você cadastrar.
4. Em **Authentication → URL Configuration**, coloque em *Site URL* o endereço onde o app vai ficar (passo 3).

### 2. Criar o primeiro administrador
1. Em **Authentication → Users → Add user**, crie seu login (e-mail + senha, marque *Auto Confirm*).
2. No SQL Editor, rode o bloco do fim do `schema.sql` com o seu e-mail:
   ```sql
   insert into public.membros (user_id, email, papel)
   select id, lower(email), 'admin' from auth.users where lower(email) = lower('SEU-EMAIL@exemplo.com')
   on conflict (user_id) do update set papel = 'admin';
   ```

### 3. Configurar e publicar o app
1. Em `config.js`, preencha `SUPABASE_URL` e `SUPABASE_ANON_KEY` (Project Settings → API). A chave *anon* pode ficar no código: quem protege os dados são as regras do banco.
2. Publique no **GitHub Pages**: Settings → Pages → *Deploy from a branch* → `main` / `(root)`. O app fica em `https://SEU-USUARIO.github.io/NOME-DO-REPO/`.
   Vercel, Netlify ou Cloudflare Pages também funcionam (site estático, sem build).
3. Abra o endereço, entre com seu login e cadastre as serventias na engrenagem.

### 4. Dar acesso aos cartórios
1. Crie o login da pessoa em **Authentication → Users → Add user**.
2. No app, vá em **Cadastros → Vincular usuário**, informe o e-mail e escolha o papel:
   - **Cartório**: vê e edita só a serventia vinculada.
   - **Assessoria**: vê e edita todas as serventias.
   - **Administrador**: tudo, mais cadastros, acessos e parâmetros.

A separação é feita **no próprio banco** (Row Level Security). Mesmo quem tentar acessar a API direto não lê dados de outra serventia.

---

## Instalar no celular
- **Android (Chrome):** abra o endereço e toque em "Instalar" no aviso do app ou no menu ⋮ → *Instalar app*.
- **iPhone (Safari):** botão Compartilhar → *Adicionar à Tela de Início*.

## Atualizar uma versão publicada
Depois de alterar os arquivos, aumente `VERSION` em `sw.js` (ex.: `gestao-v2`). Assim os aparelhos baixam a versão nova.

## Estrutura
```
index.html                     app completo (interface e regras de negócio)
config.js                      endereço e chave pública do Supabase
sw.js, manifest.webmanifest    PWA (offline e instalação)
icons/                         ícones do app
supabase/schema.sql            tabelas, regras de acesso e tempo real
```

## Observações
- **Prestação de contas:** segue o Manual do Balancete COBJUD (TJPI/FERMOJUPI, ago/2025). Os itens 1.3.1 e 2.1.3.1 são informativos. O teto do interino (90,25% do subsídio de Ministro do STF) é informado em Cadastros e precisa ser atualizado quando o subsídio mudar.
- **PQTA:** os itens e os pontos vêm da Lista de Verificação PQTA 2026 v.01 (Anoreg). A pontuação conta "parcialmente conforme" como 50% e é só uma estimativa interna.
- **Dados pessoais (LGPD):** os pedidos de minuta devem trazer só os dados necessários ao ato.
