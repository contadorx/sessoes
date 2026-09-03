-- =====================================================================
-- 0086 · O piso da pesquisa estava só no banco
-- =====================================================================
--
-- Achado rodando a suíte `0044_panorama.sql`, na verificação 5 — *"o CHECK
-- barra lixo"*:
--
--     5 · o CHECK aceitou texto curto demais
--
-- A suíte insere, como `anon`, uma resposta aberta com `dia = 'curto'` (cinco
-- caracteres) e espera ser recusada. Não foi.
--
-- ## O que estava escrito, e o que estava valendo
--
-- A `0044` criou a policy com `length(dia) between 20 and 8000`; a `0044c`
-- subiu o teto para 40000 e **manteve o piso em 20**. No banco, hoje:
--
--     length(dia) >= 1 and length(dia) <= 40000
--     length(irritante) >= 1 ...
--     length(preocupacao) >= 1 ...
--
-- **Nenhuma migração jamais escreveu `>= 1`.** Varri as 126 atrás da policy:
-- ela aparece duas vezes, na 0044 e na 0044c, e as duas dizem 20/10/10. O piso
-- foi baixado direto no banco, sem arquivo e sem motivo escrito.
--
-- É a **lei 5** furada pela terceira vez em 03/09 — as outras duas foram as
-- policies de `ofertas_fixas`, na 0084. E é uma variante pior que aquela: lá o
-- banco tinha **a mais** que o repositório, e o defeito só aparecia em base
-- nova. Aqui o banco tem **outra coisa**, e o repositório descreve um produto
-- que não é o que está no ar.
--
-- ## A decisão, e de quem ela é
--
-- Perguntei antes de mexer, porque as duas leituras eram defensáveis e nenhuma
-- é minha: **20 é um portão de qualidade, 1 é uma porta aberta**, e a pesquisa
-- é pública e está no ar. Baixar o piso é exatamente o que alguém faz quando
-- vê uma respondente de verdade esbarrar nele — e uma resposta curta e honesta
-- vale mais que um campo vazio.
--
-- A resposta foi que **o banco está certo**. Então esta migração não muda
-- comportamento nenhum: ela **registra** o que já vale, para o repositório
-- voltar a descrever o banco e para um restore não desfazer a decisão em
-- silêncio. As outras duas policies da pesquisa (`pesquisa_respostas` e
-- `pesquisa_contatos`) foram conferidas contra a 0044c e batem — só esta
-- divergia.
--
-- O teto de 40000 e os limites de `canal`, `canal_url` e `ua` seguem como a
-- 0044c os deixou: eles são contra abuso, não contra pessoa, e isso não mudou.
-- =====================================================================

drop policy if exists "qualquer um responde a aberta" on public.pesquisa_abertas;

create policy "qualquer um responde a aberta" on public.pesquisa_abertas
  for insert to anon, authenticated
  with check (
    -- Piso de 1, e não de 20: quem responde a uma pesquisa pública escreve o
    -- que tem para escrever. O limite de cima é que protege contra abuso.
    length(dia) between 1 and 40000
    and length(irritante) between 1 and 40000
    and length(preocupacao) between 1 and 40000
    and (gambiarra is null or length(gambiarra) <= 40000)
    and (canal is null or length(canal) <= 60)
    and (canal_url is null or length(canal_url) <= 40)
    and (ua is null or length(ua) <= 200)
  );

comment on policy "qualquer um responde a aberta" on public.pesquisa_abertas is
  'Piso de 1 caractere, registrado na 0086: era 20 nas migracoes 0044/0044c e 1 no banco, sem arquivo que explicasse. A decisao e o 1 — resposta curta e honesta vale mais que campo vazio. O teto de 40000 e contra abuso, nao contra pessoa.';
