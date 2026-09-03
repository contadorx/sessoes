-- Teste do espelho da lista de planos (B46, migração 0070).
--
-- **A outra metade de um espelho que estava quebrado de um lado só.**
--
-- A 0064 criou `planos.por_vir` e a restrição `planos_promessa_nao_e_recurso`
-- para que promessa não pudesse ser vendida como recurso. E a promessa voltou
-- assim mesmo — "com aprovação em etapas", no cartão de R$ 129 — porque a trava
-- mora nesta coluna e **a landing renderiza a constante do TypeScript**.
--
-- Então a lista está escrita duas vezes de propósito, como a dos templates na
-- 0066: aqui, contra o banco; e em `lib/planos.test.ts`, contra a migração.
-- Uma metade que mude sozinha reprova.
--
--   1. os quatro planos existem e são públicos
--   2. `recursos` é exatamente a lista canônica, plano a plano       ← decide
--   3. `por_vir` idem                                               ← decide
--   4. as duas continuam disjuntas — a restrição da 0064 viva
--   5. nenhuma palavra morta está sendo vendida
--
-- A comparação é feita em minúsculas: o banco escreve o primeiro caractere em
-- caixa baixa por convenção da casa, e isso é apresentação. Conteúdo diferente
-- reprova.
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0070_a_lista_de_planos_e_uma_so.sql

do $do$
declare
  v_esperado text[];
  v_achado   text[];
  v_n        integer;
  v_codigo   text;
begin

-- 1 · os quatro planos existem e são públicos.
select count(*)::integer into v_n from public.planos where ativo and publico;
if v_n <> 4 then
  raise exception 'FALHOU 1: são % planos públicos ativos, e a vitrine mostra quatro', v_n;
end if;

-- 2 · gratis · recursos
v_esperado := array[
    lower('Agenda, prontuário e o registro do que aconteceu com cada horário'),
    lower('Pacientes sem limite'),
    lower('Sessões sem limite'),
    lower('Fila e página da vaga, completas'),
    lower('Lembrete de véspera e aviso de desmarque saem sozinhos'),
    lower('Política de cancelamento congelada no contrato'),
    lower('Cobrança, recibo e informe'),
    lower('A fila e a cobrança saem do seu WhatsApp, com um toque seu')
  ];
select array_agg(lower(x) order by ord) into v_achado
  from public.planos p, unnest(p.recursos) with ordinality as t(x, ord)
 where p.codigo = 'gratis';
if coalesce(v_achado, '{}'::text[]) is distinct from v_esperado then
  raise exception 'FALHOU 2: recursos de gratis no banco é % e a lista canônica é % — duas descrições do mesmo produto, e a que ninguém vê é a que está protegida', coalesce(v_achado, '{}'::text[]), v_esperado;
end if;

-- 3 · gratis · por_vir
v_esperado := '{}'::text[];
select array_agg(lower(x) order by ord) into v_achado
  from public.planos p, unnest(p.por_vir) with ordinality as t(x, ord)
 where p.codigo = 'gratis';
if coalesce(v_achado, '{}'::text[]) is distinct from v_esperado then
  raise exception 'FALHOU 3: por_vir de gratis no banco é % e a lista canônica é % — duas descrições do mesmo produto, e a que ninguém vê é a que está protegida', coalesce(v_achado, '{}'::text[]), v_esperado;
end if;

-- 4 · solo · recursos
v_esperado := array[
    lower('Tudo do Gratuito'),
    lower('A fila e a cobrança saem sozinhas, na hora em que a vaga abre'),
    lower('60 sessões por mês'),
    lower('Modo Receita Saúde e pasta do contador'),
    lower('Régua de atraso impessoal'),
    lower('Receita por hora disponível e o que aconteceu com cada horário')
  ];
select array_agg(lower(x) order by ord) into v_achado
  from public.planos p, unnest(p.recursos) with ordinality as t(x, ord)
 where p.codigo = 'solo';
if coalesce(v_achado, '{}'::text[]) is distinct from v_esperado then
  raise exception 'FALHOU 4: recursos de solo no banco é % e a lista canônica é % — duas descrições do mesmo produto, e a que ninguém vê é a que está protegida', coalesce(v_achado, '{}'::text[]), v_esperado;
end if;

-- 5 · solo · por_vir
v_esperado := '{}'::text[];
select array_agg(lower(x) order by ord) into v_achado
  from public.planos p, unnest(p.por_vir) with ordinality as t(x, ord)
 where p.codigo = 'solo';
if coalesce(v_achado, '{}'::text[]) is distinct from v_esperado then
  raise exception 'FALHOU 5: por_vir de solo no banco é % e a lista canônica é % — duas descrições do mesmo produto, e a que ninguém vê é a que está protegida', coalesce(v_achado, '{}'::text[]), v_esperado;
end if;

-- 6 · pro · recursos
v_esperado := array[
    lower('Tudo do Consultório'),
    lower('Sem faixa de sessões'),
    lower('Permissões por pessoa: quem vê o quê')
  ];
select array_agg(lower(x) order by ord) into v_achado
  from public.planos p, unnest(p.recursos) with ordinality as t(x, ord)
 where p.codigo = 'pro';
if coalesce(v_achado, '{}'::text[]) is distinct from v_esperado then
  raise exception 'FALHOU 6: recursos de pro no banco é % e a lista canônica é % — duas descrições do mesmo produto, e a que ninguém vê é a que está protegida', coalesce(v_achado, '{}'::text[]), v_esperado;
end if;

-- 7 · pro · por_vir
v_esperado := array[
    lower('NFS-e para quem atende como PJ'),
    lower('Número próprio: as mensagens chegam do número que suas pacientes já conhecem'),
    lower('Página do paciente: confirmar, pagar e receber documento'),
    lower('Reajuste assistido e modo férias'),
    lower('Aprovação em etapas para quem tem permissão limitada')
  ];
select array_agg(lower(x) order by ord) into v_achado
  from public.planos p, unnest(p.por_vir) with ordinality as t(x, ord)
 where p.codigo = 'pro';
if coalesce(v_achado, '{}'::text[]) is distinct from v_esperado then
  raise exception 'FALHOU 7: por_vir de pro no banco é % e a lista canônica é % — duas descrições do mesmo produto, e a que ninguém vê é a que está protegida', coalesce(v_achado, '{}'::text[]), v_esperado;
end if;

-- 8 · clinica · recursos
v_esperado := array[
    lower('Tudo do Consultório Completo'),
    lower('Vários profissionais, com sigilo entre eles por construção'),
    lower('Sem faixa de sessões, por profissional que atende')
  ];
select array_agg(lower(x) order by ord) into v_achado
  from public.planos p, unnest(p.recursos) with ordinality as t(x, ord)
 where p.codigo = 'clinica';
if coalesce(v_achado, '{}'::text[]) is distinct from v_esperado then
  raise exception 'FALHOU 8: recursos de clinica no banco é % e a lista canônica é % — duas descrições do mesmo produto, e a que ninguém vê é a que está protegida', coalesce(v_achado, '{}'::text[]), v_esperado;
end if;

-- 9 · clinica · por_vir
v_esperado := array[
    lower('Repasse e demonstrativo por profissional'),
    lower('Agenda de salas'),
    lower('Fiscal consolidado da clínica'),
    lower('Fila cruzada entre profissionais'),
    lower('Número próprio da clínica')
  ];
select array_agg(lower(x) order by ord) into v_achado
  from public.planos p, unnest(p.por_vir) with ordinality as t(x, ord)
 where p.codigo = 'clinica';
if coalesce(v_achado, '{}'::text[]) is distinct from v_esperado then
  raise exception 'FALHOU 9: por_vir de clinica no banco é % e a lista canônica é % — duas descrições do mesmo produto, e a que ninguém vê é a que está protegida', coalesce(v_achado, '{}'::text[]), v_esperado;
end if;

-- 10 · recursos e por_vir continuam disjuntas — a restrição da 0064 viva.
for v_codigo in select codigo from public.planos loop
  select count(*)::integer into v_n
    from public.planos p
   where p.codigo = v_codigo and p.recursos && p.por_vir;
  if v_n > 0 then
    raise exception 'FALHOU 10: em % há linha que é recurso e promessa ao mesmo tempo', v_codigo;
  end if;
end loop;

-- 11 · nenhuma palavra morta está sendo vendida. A lista é das mortas, não das
--      vivas: enumerar o que existe é a checagem que esquece o item novo.
select count(*)::integer into v_n
  from public.planos p, unnest(p.recursos) as r(linha)
 where lower(r.linha) similar to '%(briefing|radar de furo|portal do paciente|nfs-e|salas|repasse|fila cruzada|fila limitada)%';
if v_n > 0 then
  raise exception 'FALHOU 11: % linha(s) de recurso vendem coisa morta ou inexistente', v_n;
end if;

raise notice 'OK · 0070 · a lista de planos é uma só, nos dois lados';
end
$do$;
