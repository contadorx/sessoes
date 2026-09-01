-- 0044c · O teto do jsonb não pode perder resposta.
-- JÁ APLICADA no projeto remoto em 01/09/2026.
--
-- O objeto respostas carrega tambem os textos abertos (q11..q14, q57,
-- q64, q66, q81), e nenhum textarea do formulario tem maxlength. Com o
-- teto em 60 mil, uma respondente prolixa teria o questionario INTEIRO
-- recusado no envio final — e nao veria erro nenhum, porque o envio e
-- best-effort. Perder um questionario completo por prolixidade e o pior
-- modo de falha possivel nesta pesquisa. Sobe para 400 mil: limite
-- contra abuso, nao contra pessoa.

drop policy "qualquer um responde o questionario" on public.pesquisa_respostas;

create policy "qualquer um responde o questionario" on public.pesquisa_respostas
  for insert to anon, authenticated with check (
    jsonb_typeof(respostas) = 'object'
    and length(respostas::text) <= 400000
    and (duracao_seg is null or duracao_seg between 0 and 86400)
    and (canal is null or length(canal) <= 60)
    and (canal_url is null or length(canal_url) <= 40)
    and (ordem_itens is null or array_length(ordem_itens, 1) <= 40)
  );

drop policy "qualquer um responde a aberta" on public.pesquisa_abertas;

create policy "qualquer um responde a aberta" on public.pesquisa_abertas
  for insert to anon, authenticated with check (
    length(dia) between 20 and 40000
    and length(irritante) between 10 and 40000
    and length(preocupacao) between 10 and 40000
    and (gambiarra is null or length(gambiarra) <= 40000)
    and (canal is null or length(canal) <= 60)
    and (canal_url is null or length(canal_url) <= 40)
    and (ua is null or length(ua) <= 200)
  );
