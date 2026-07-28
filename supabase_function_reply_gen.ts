// ============================================================
// Supabase Edge Function : reply-gen
// Google口コミへの返信文を Claude (claude-opus-5) で生成する
//
// 設置方法 (Supabaseダッシュボードだけで完結・CLI不要):
//   1. Supabase -> Edge Functions -> Deploy a new function -> Via Editor
//   2. 関数名を reply-gen にして、このファイルの中身を貼り付けて Deploy
//   3. Edge Functions -> reply-gen -> Details で「Verify JWT」をOFFにする
//      (アプリはpublishableキーで呼ぶため)
//   4. Project Settings -> Edge Functions -> Secrets に
//      ANTHROPIC_API_KEY = sk-ant-... を追加
// ============================================================
import Anthropic from "npm:@anthropic-ai/sdk";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { pass, store, review, menus, samples } = await req.json();

    // オーナーパスワードをDB(rvw_pass_ok)で照合。オーナー以外はAI生成を使えない
    const supaUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (supaUrl && anonKey) {
      const chk = await fetch(`${supaUrl}/rest/v1/rpc/rvw_pass_ok`, {
        method: "POST",
        headers: {
          apikey: anonKey,
          Authorization: `Bearer ${anonKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ p_pass: pass ?? "" }),
      });
      const ok = chk.ok ? await chk.json() : false;
      if (ok !== true) {
        return new Response(JSON.stringify({ error: "password_ng" }), {
          status: 401,
          headers: { ...cors, "Content-Type": "application/json" },
        });
      }
    }

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "no_api_key" }), {
        status: 500,
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }
    const client = new Anthropic({ apiKey });

    const fewshot = (samples ?? [])
      .map((s: { review_body: string; reply_body: string }) =>
        `【口コミ】\n${s.review_body}\n【お店の返信】\n${s.reply_body}`)
      .join("\n\n");

    const system =
      `あなたは日本の個人経営の隠れ家居酒屋「${store}」の店主です。Googleマップの口コミに、店主として返信文を書きます。

ルール:
- 過去の返信のお手本があれば、その口調・文体・締めの挨拶をできるだけ再現する
- お客様の口コミの内容(褒められた料理・指摘された点)に必ず具体的に触れる
- メニュー名に触れる場合は、実際のメニュー一覧にある正確な名前を使う
- 低評価(星1〜2)には言い訳をせず誠実に謝罪し、改善の姿勢を伝える
- 200〜300字程度。絵文字は使わない。宣伝しすぎない
- 返信文だけを出力する(前置きや説明は書かない)`;

    const user = `${fewshot ? "■過去の返信のお手本:\n" + fewshot + "\n\n" : ""}` +
      `■お店のメニュー(参考):\n${(menus ?? []).join("、")}\n\n` +
      `■今回返信する口コミ:\n投稿者: ${review.author || "名無し"}\n` +
      `評価: 星${review.rating}\n本文:\n${review.body}\n\n` +
      `この口コミへの返信文を書いてください。`;

    const msg = await client.messages.create({
      model: "claude-opus-5",
      max_tokens: 2000,
      system,
      messages: [{ role: "user", content: user }],
    });

    if (msg.stop_reason === "refusal") throw new Error("refusal");
    const reply = msg.content
      .filter((b) => b.type === "text")
      .map((b) => (b as { text: string }).text)
      .join("")
      .trim();
    if (!reply) throw new Error("empty");

    return new Response(JSON.stringify({ reply }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
