// Supabase Edge Function: gera o rascunho de uma minuta com a API da Anthropic.
// Publicar:  supabase functions deploy gerar-minuta
// Segredo:   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
// A função só atende usuários com papel "admin" ou "assessoria" e lê a minuta
// com as permissões do próprio usuário (as regras do banco continuam valendo).

import { createClient } from "jsr:@supabase/supabase-js@2";

const MODEL = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5-5";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: ok } = await supabase.rpc("is_assessoria");
    if (!ok) return json({ error: "Apenas a assessoria pode gerar minutas." }, 403);

    const { minutaId } = await req.json();
    const { data: row, error } = await supabase.from("minutas").select("data, serventia_id").eq("id", minutaId).single();
    if (error || !row) return json({ error: "Minuta não encontrada." }, 404);
    const { data: sv } = await supabase.from("serventias").select("data").eq("id", row.serventia_id).single();
    const m = row.data ?? {};
    const s = sv?.data ?? {};

    const prompt = `Você é assessor jurídico de serventias extrajudiciais no Piauí (Brasil). Redija a MINUTA completa do ato abaixo, em português jurídico formal, pronta para revisão do tabelião/registrador.
Regras:
- Use somente os dados fornecidos. Onde faltar dado (qualificação, números de documentos, matrícula, valores, datas, ITBI/ITCMD, certidões), deixe um campo entre colchetes, como [CPF DO VENDEDOR].
- Não invente números, nomes, dados registrais ou fiscais.
- Estruture conforme a prática notarial/registral: título, qualificação das partes, objeto, cláusulas, declarações, documentos apresentados, emolumentos e encerramento, conforme o tipo de ato.
- Cite fundamentos legais apenas quando forem seguros (ex.: Lei 6.015/1973, Lei 8.935/1994, Lei 7.433/1985, Código Civil, Provimento CNJ 149/2023, Código de Normas do TJPI).
- Devolva apenas o texto da minuta, sem comentários antes ou depois.

Serventia: ${s.nome ?? ""} — ${s.municipio ?? ""}/PI (${s.especialidade ?? "especialidade não informada"})
Tipo de ato: ${m.tipo ?? ""}
Partes: ${m.partes ?? ""}
Objeto: ${m.objeto || "[não informado]"}
Detalhes/cláusulas específicas: ${m.detalhes || "[nenhum]"}`;

    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify({ model: MODEL, max_tokens: 8000, messages: [{ role: "user", content: prompt }] }),
    });
    const out = await r.json();
    if (!r.ok) return json({ error: out?.error?.message ?? "Falha na API da Anthropic." }, 502);
    const text = (out.content ?? []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("");
    return json({ text, truncated: out.stop_reason === "max_tokens" });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
