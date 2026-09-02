-- Teste do desenho de planos (migração 0064).
--
-- Esta suíte é quase toda de ausência, e não por estilo: a 0064 **não constrói
-- recurso nenhum**. Ela conserta quatro afirmações falsas. Um conserto de
-- afirmação não deixa código novo para exercitar — deixa só a possibilidade de
-- a afirmação falsa voltar. Então é isso que se verifica.
--
-- Cinco decidem o arquivo:
--
--   · a **2**, que exige que os `codigo` **não** tenham mudado com os nomes. Foi
--     a decisão de desenho da migração: nome é palavra dela, código é palavra do
--     sistema. Se alguém "arrumar" o código para casar com o nome novo, a chave
--     estrangeira de `contas.plano` cai junto com a URL da landing;
--   · a **5**, que percorre 1 a 8 profissionais e exige que a faixa **nunca
--     desça** de um degrau pago para o seguinte. É o defeito que originou a
--     build: a Clínica custava R$ 120 a mais que o Pro e dava 140 sessões a
--     menos. Um número só não pega isso — só pega quem varre a escada inteira;
--   · a **9**, que põe quarenta sessões numa conta Gratuita sem faixa e exige
--     que todas entrem. É a 2 da suíte 0060 pelo outro lado: lá a faixa existia
--     e não barrava; aqui ela não existe e continua não barrando;
--   · a **15**, que varre `recursos` de todos os planos atrás das oito palavras
--     que descreviam software inexistente. É a verificação que impede a 0045 de
--     ser desobedecida de novo — e ela reprova mesmo quem acrescentar a palavra
--     de boa-fé, achando que "vai sair mês que vem";
--   · a **17**, que tenta pôr a mesma linha em `recursos` e em `por_vir` e exige
--     que o **banco** recuse. Sem essa restrição, `por_vir` seria só um segundo
--     lugar para prometer, e o defeito voltaria com roupa nova.
--
-- **Uma armadilha evitada, e ela é cicatriz de três dias atrás:** todas as
-- varreduras de corpo de função usam `position(... in ...)` e nunca `like`. Em
-- `LIKE`, `_` é curinga — foi assim que a verificação 9 da suíte 0060 acusou
-- código correto, casando `cabe_no_teto` com o comentário "(cabe no teto?)".
-- Toda palavra procurada aqui tem `_` no meio.
--
--   parte 1 · o nome é dela, o código é do sistema
--     1. os quatro nomes são os do `claude/25`
--     2. os quatro códigos NÃO mudaram, e toda conta ainda acha o plano  ← decide
--     3. o vocabulário velho saiu inteiro: nenhum plano se chama Pro
--
--   parte 2 · a escada não desce
--     4. o preço sobe do primeiro ao último degrau
--     5. a faixa nunca desce, de 1 a 8 profissionais                     ← decide
--     6. a Clínica de uma profissional empata com o Completo
--     7. a Clínica de quatro quadruplica, e é o caso da landing
--
--   parte 3 · o Gratuito perdeu a faixa e não ganhou trava
--     8. o Gratuito não tem faixa — e o limite dele é o canal, não um número
--     9. a quadragésima sessão de uma conta Gratuita ENTRA               ← decide
--    10. `contas_acima_da_faixa` não enxerga mais conta gratuita
--    11. mas o medidor enxerga — e para de enxergar quando é conta de teste
--    12. o medidor não escreve nada, em lugar nenhum
--    13. quem não é operador leva recusa DITA, e não zero linhas         ← decide
--    14. o anônimo não executa o medidor
--
--   parte 4 · `recursos` só descreve o que existe
--    15. nenhuma das oito palavras mortas está em `recursos`             ← decide
--    16. quatro delas estão em `por_vir` — sumir não é o mesmo que resolver
--    17. o banco recusa a mesma linha nas duas listas                    ← decide
--    18. e recusa também quando a interseção é de um item entre muitos
--    19. nenhum plano ficou com `recursos` vazio
--    20. o Gratuito não tem `por_vir`: ele não é degrau de promessa
--
--   parte 5 · o preço por profissional, e o que ele ainda NÃO faz
--    21. só a Clínica tem preço por profissional
--    22. a fatura continua lendo `preco_centavos` e ignora o número novo ← decide
--    23. 24900 + 4 × 3900 = 40500, o número da landing
--
--   parte 6 · nada disto virou cerca
--    24. só `faixa_da_conta` lê `limite_sessoes_mes` no banco inteiro    ← decide
--    25. "sem faixa" no cartão e `faixa_e_fair_use` no banco andam juntos ← decide
--    26. o número próprio só é prometido no plano em que ele vai morar   ← decide
--
-- Levanta exceção no primeiro furo. Silêncio = passou.
-- Rodar com: supabase db execute -f supabase/tests/0064_os_planos_e_o_degrau.sql

do $do$
declare
  v_a_auth  uuid := '11111111-1111-4111-8111-111111111164';
  v_b_auth  uuid := '22222222-2222-4222-8222-222222222164';
  v_a_conta uuid; v_a_prof uuid;
  v_b_conta uuid;
  v_ana     uuid;
  v_hoje    date;
  v_n       integer;
  v_k       integer;
  v_lim     integer;
  v_ant     integer;
  v_txt     text;
  v_def     text;
  v_erro    text;
  v_planos  text[] := array['gratis', 'solo', 'pro', 'clinica'];
  v_mortas  text[] := array['briefing', 'radar de furo', 'portal do paciente',
                            'NFS-e', 'salas', 'repasse', 'fila cruzada',
                            'fila limitada'];
  v_achou   text;
  v_faixa   record;
begin

-- ============================================================ preâmbulo

-- A limpeza vai em ordem de dependência, e a ordem não é decorativa:
-- `pacientes` e `sessoes` apontam para `profissionais` com `on delete
-- restrict`, e apagar `auth.users` desce em cascata até `profissionais`. Se as
-- duas primeiras não saírem antes, a **segunda** rodada desta suíte morre aqui
-- no preâmbulo com violação de chave estrangeira — e morre justamente porque a
-- verificação 9 deixa quarenta sessões e uma paciente no banco. Uma suíte que
-- só passa em banco limpo é uma suíte que passa uma vez.
delete from public.sessoes
 where conta_id in (select id from public.contas
                     where nome in ('Planos Teste', 'Planos Vizinha'));
delete from public.pacientes
 where conta_id in (select id from public.contas
                     where nome in ('Planos Teste', 'Planos Vizinha'));
delete from auth.users where id in (v_a_auth, v_b_auth);
delete from public.contas where nome in ('Planos Teste', 'Planos Vizinha');

insert into auth.users (id, email, raw_user_meta_data)
  values (v_a_auth, 'planos@teste.sessoes.com.br', '{"nome":"Planos Teste"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data)
  values (v_b_auth, 'planosviz@teste.sessoes.com.br', '{"nome":"Planos Vizinha"}'::jsonb);

select conta_id into v_a_conta from public.usuarios where auth_user_id = v_a_auth;
select id      into v_a_prof  from public.profissionais where conta_id = v_a_conta;
select conta_id into v_b_conta from public.usuarios where auth_user_id = v_b_auth;

v_hoje := public.hoje_sp();

-- A conta nasce no Gratuito pelo gatilho de signup, que é onde ela precisa
-- estar para as partes 3. E ela nasce marcada como teste ou não conforme o
-- padrão da coluna — a verificação 11 depende de os dois valores serem
-- alcançáveis, então o preâmbulo fixa o primeiro explicitamente.
set local role postgres;
update public.contas set plano = 'gratis', is_teste = false where id = v_a_conta;
reset role;

perform set_config('request.jwt.claims',
  json_build_object('sub', v_a_auth::text, 'role', 'authenticated')::text, true);
set local role authenticated;
insert into public.pacientes (profissional_id, nome, telefone, estado)
  values (v_a_prof, 'Ana Planos', '5511900000641', 'em_atendimento') returning id into v_ana;
reset role;

raise notice '--- parte 1 · o nome é dela, o código é do sistema ---';

-- 1 · Os nomes do `claude/25`, revisão 4.
select string_agg(nome, ' | ' order by preco_centavos) into v_txt from public.planos;
if v_txt <> 'Gratuito | Consultório | Consultório Completo | Clínica' then
  raise exception 'FALHOU 1: os nomes são "%" — o `claude/25` fecha Gratuito, Consultório, Consultório Completo, Clínica', v_txt;
end if;
raise notice 'ok 1 · os quatro nomes são os do doc 25';

-- 2 · E os códigos NÃO mudaram.  ← decide
--
-- Esta é a verificação que protege a decisão de desenho da 0064. Um rename de
-- marketing que descesse até o `codigo` levaria junto a chave estrangeira de
-- `contas.plano`, a URL `/entrar?criar&plano=solo`, os metadados do cadastro e
-- catorze arquivos — e ninguém veria diferença nenhuma na tela.
select array_agg(codigo order by preco_centavos) into v_planos from public.planos;
if v_planos <> array['gratis', 'solo', 'pro', 'clinica'] then
  raise exception 'FALHOU 2: os códigos viraram % — o código é a palavra do sistema e não muda por nome comercial', v_planos;
end if;

-- E a consequência disso, provada em vez de assumida: nenhuma conta ficou
-- apontando para plano que não existe.
select count(*)::integer into v_n
  from public.contas ct
 where not exists (select 1 from public.planos pl where pl.codigo = ct.plano);
if v_n > 0 then
  raise exception 'FALHOU 2: % conta(s) apontam para plano inexistente', v_n;
end if;
raise notice 'ok 2 · códigos intactos e nenhuma conta órfã';

-- 3 · O vocabulário velho saiu inteiro.
--
-- Meio-rename é pior do que nenhum: a psicóloga lê "Consultório Completo" na
-- landing e "Pro" no e-mail de cobrança, e conclui que são dois produtos.
select string_agg(nome, ', ') into v_txt
  from public.planos
 where nome in ('Pro', 'Solo', 'Grátis', 'Gratis');
if v_txt is not null then
  raise exception 'FALHOU 3: sobrou nome antigo: %', v_txt;
end if;
raise notice 'ok 3 · nenhum plano se chama mais Pro, Solo ou Grátis';

raise notice '--- parte 2 · a escada não desce ---';

-- 4 · O preço sobe.
v_ant := -1;
for v_lim in select preco_centavos from public.planos order by ordem, preco_centavos loop
  if v_lim <= v_ant then
    raise exception 'FALHOU 4: a escada de preço desce ou empata em % centavos', v_lim;
  end if;
  v_ant := v_lim;
end loop;
raise notice 'ok 4 · o preço sobe do primeiro ao último degrau';

-- 5 · A FAIXA NUNCA DESCE, de 1 a 8 profissionais.  ← decide
--
-- É o defeito que originou esta build. Antes da 0064: Pro 200 fixo, Clínica 60
-- por profissional — uma clínica de uma pessoa pagava R$ 120 a mais para
-- receber 140 sessões a menos, e a de duas ainda ficava atrás.
--
-- A varredura é por número de profissionais porque **o defeito só existe em
-- alguns valores**. Com quatro profissionais a Clínica antiga dava 240 contra
-- 200 do Pro e parecia certa; a inversão morava em 1, 2 e 3. Verificação que
-- olha um caso não pega defeito que depende do caso.
--
-- O Gratuito fica **fora desta varredura**, e o motivo precisa estar escrito:
-- ele não tem faixa, e não ter faixa não é ter faixa infinita. O limite do
-- Gratuito é o canal — a mensagem espera o dedo dela (OP9). Comparar `null` com
-- 60 e chamar de descida seria comparar duas espécies diferentes de limite.
for v_k in 1..8 loop
  v_ant := -1;
  for v_lim in
    select coalesce(pl.limite_sessoes_mes, 0) * v_k
      from public.planos pl
     where pl.codigo <> 'gratis'
     order by pl.preco_centavos
  loop
    if v_lim < v_ant then
      raise exception 'FALHOU 5: com % profissional(is) a escada desce — % depois de %. É o degrau que a 0064 desfez, e ele voltou', v_k, v_lim, v_ant;
    end if;
    v_ant := v_lim;
  end loop;
end loop;
raise notice 'ok 5 · de 1 a 8 profissionais, a faixa nunca desce';

-- 6 · A Clínica de uma profissional empata com o Completo, e não fica abaixo.
select limite_sessoes_mes into v_lim from public.planos where codigo = 'clinica';
select limite_sessoes_mes into v_ant from public.planos where codigo = 'pro';
if v_lim < v_ant then
  raise exception 'FALHOU 6: Clínica % contra Completo % — com uma profissional, o plano mais caro dá menos', v_lim, v_ant;
end if;
raise notice 'ok 6 · a Clínica de uma profissional não fica abaixo do Completo';

-- 7 · E a de quatro quadruplica — é o caso escrito na landing.
if v_lim * 4 <> 800 then
  raise exception 'FALHOU 7: quatro profissionais dão % sessões (esperado 800)', v_lim * 4;
end if;
raise notice 'ok 7 · quatro profissionais, 800 sessões';

raise notice '--- parte 3 · o Gratuito perdeu a faixa e não ganhou trava ---';

-- 8 · O Gratuito não tem faixa, e o limite dele é o canal.
set local role authenticated;
select * into v_faixa from public.faixa_da_conta(v_a_conta);
reset role;
if v_faixa.tem_faixa then
  raise exception 'FALHOU 8: o Gratuito voltou a ter faixa (%) — a auditoria do claude/25 mostrou que 8 sessões é a fila não acontecendo', v_faixa.limite;
end if;

-- A metade que torna a frase acima verdadeira em vez de bonita: o limite do
-- Gratuito existe, e é o canal manual da OP9. Se alguém tirar a faixa E o
-- canal manual, o Gratuito vira o produto pago de graça.
select canal_saida into v_txt from public.planos where codigo = 'gratis';
if v_txt <> 'manual' then
  raise exception 'FALHOU 8: o Gratuito ficou sem faixa E com canal "%" — sem os dois limites, ele é o plano pago de graça', v_txt;
end if;
select count(*)::integer into v_n from public.planos
 where codigo <> 'gratis' and canal_saida <> 'plataforma';
if v_n > 0 then
  raise exception 'FALHOU 8: % plano(s) pago(s) saíram do canal automático', v_n;
end if;
raise notice 'ok 8 · sem faixa, e o limite é o dedo dela';

-- 9 · A quadragésima sessão entra.  ← decide
--
-- A 2 da suíte 0060 provou que a faixa não barra. Esta prova o caso que a 0064
-- criou: **sem faixa nenhuma**, nada apareceu no lugar dela. Quarenta sessões
-- é o volume de quem atende dez por semana — exatamente a conta gratuita de
-- alto volume de que o `claude/25` fala.
set local role postgres;
for v_k in 1..40 loop
  insert into public.sessoes
    (conta_id, profissional_id, paciente_id, inicio, fim, origem, estado, valor,
     politica_horas, politica_percentual)
    values (v_a_conta, v_a_prof, v_ana,
            (v_hoje + time '07:00' + make_interval(mins => v_k * 20))
              at time zone 'America/Sao_Paulo',
            (v_hoje + time '07:15' + make_interval(mins => v_k * 20))
              at time zone 'America/Sao_Paulo',
            'avulsa', 'prevista', 200.00, 24, 50);
end loop;
reset role;

select count(*)::integer into v_n from public.sessoes
 where conta_id = v_a_conta and estado = 'prevista';
if v_n <> 40 then
  raise exception 'FALHOU 9: só % das 40 sessões entraram numa conta sem faixa', v_n;
end if;
raise notice 'ok 9 · quarenta sessões numa conta gratuita, e nada barrou';

-- 10 · E o operador não a enxerga mais pela faixa.
--
-- **Esta verificação afirma um prejuízo, e é de propósito.** Tirar a faixa do
-- Gratuito custa exatamente isto: a lista que eu olhava para pedir upgrade
-- deixa de mostrar a conta gratuita. Está aqui para que ninguém descubra
-- sozinho daqui a dois meses e ache que é bug.
set local role postgres;
update public.usuarios set operador = true where auth_user_id = v_a_auth;
reset role;

set local role authenticated;
select count(*)::integer into v_n
  from public.contas_acima_da_faixa() f where f.conta_id = v_a_conta;
reset role;
if v_n > 0 then
  raise exception 'FALHOU 10: a conta gratuita apareceu em contas_acima_da_faixa — ela não tem faixa para estourar';
end if;
raise notice 'ok 10 · a lista da faixa não enxerga o Gratuito, e isso é o preço da decisão';

-- 11 · Mas o medidor enxerga — e para de enxergar quando é conta de teste.
--
-- As duas metades importam. A primeira é o relógio dos 60 dias do `claude/25`:
-- sem ele, tirar a faixa transformaria uma hipótese testável numa opinião. A
-- segunda é que a lista do operador não pode vir suja das nossas próprias
-- contas de suíte — uma lista com lixo dentro é uma lista que ninguém abre.
set local role authenticated;
select count(*)::integer into v_n
  from public.contas_gratuitas_de_alto_volume(20) g where g.conta_id = v_a_conta;
reset role;
if v_n <> 1 then
  raise exception 'FALHOU 11: a conta com 40 sessões não apareceu no medidor';
end if;

set local role postgres;
update public.contas set is_teste = true where id = v_a_conta;
reset role;

set local role authenticated;
select count(*)::integer into v_n
  from public.contas_gratuitas_de_alto_volume(20) g where g.conta_id = v_a_conta;
reset role;
if v_n <> 0 then
  raise exception 'FALHOU 11: conta marcada como teste continuou na lista do operador';
end if;
raise notice 'ok 11 · o medidor acha a conta de alto volume, e ignora as de teste';

-- 12 · E o medidor não escreve nada.
--
-- É `stable`, e `stable` é promessa de assinatura — o corpo poderia mentir se
-- alguém trocasse por `volatile` num "só para gravar quem eu já contatei". A
-- verificação compara o estado antes e depois em vez de confiar no rótulo.
select count(*)::integer into v_n from public.sessoes where conta_id = v_a_conta;
set local role authenticated;
perform * from public.contas_gratuitas_de_alto_volume(1);
reset role;
select count(*)::integer into v_k from public.sessoes where conta_id = v_a_conta;
if v_n <> v_k then
  raise exception 'FALHOU 12: chamar o medidor mudou o número de sessões (% → %)', v_n, v_k;
end if;
select provolatile::text into v_txt from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname = 'contas_gratuitas_de_alto_volume';
if v_txt <> 's' then
  raise exception 'FALHOU 12: o medidor deixou de ser stable — volatilidade %', v_txt;
end if;
raise notice 'ok 12 · o medidor lê e não escreve';

-- 13 · Quem não é operador leva recusa DITA.  ← decide
--
-- A mesma decisão da 0063: `security definer` com exceção explícita, e não
-- policy que devolve zero linhas. Numa tela de operação, zero linhas é
-- indistinguível de "não há nenhuma conta assim" — e a diferença entre "não há"
-- e "você não pode ver" é a diferença entre uma decisão certa e uma errada.
set local role postgres;
update public.usuarios set operador = false where auth_user_id = v_a_auth;
reset role;

v_erro := null;
begin
  set local role authenticated;
  perform * from public.contas_gratuitas_de_alto_volume(1);
  reset role;
exception when others then
  v_erro := sqlerrm;
  reset role;
end;
if v_erro is null then
  raise exception 'FALHOU 13: quem não é operador leu a lista';
end if;
if position('operador' in v_erro) = 0 then
  raise exception 'FALHOU 13: a recusa não diz o motivo — veio "%"', v_erro;
end if;
raise notice 'ok 13 · a recusa é dita, e diz o nome do motivo';

-- 14 · E o anônimo nem chega lá.
v_erro := null;
begin
  set local role anon;
  perform * from public.contas_gratuitas_de_alto_volume(1);
  reset role;
exception when others then
  v_erro := sqlerrm;
  reset role;
end;
if v_erro is null then
  raise exception 'FALHOU 14: o anônimo executou o medidor';
end if;
raise notice 'ok 14 · o anônimo não executa o medidor';

raise notice '--- parte 4 · recursos só descreve o que existe ---';

-- 15 · Nenhuma palavra morta em `recursos`.  ← decide
--
-- Antes da 0064, oito das treze linhas de `recursos` descreviam software que
-- não existe: briefing, radar de furo e portal do paciente foram mortos pelo
-- doc 30; NFS-e é a B38; salas, repasse e fila cruzada são fase 4. E "fila
-- limitada" no Gratuito era falso no sentido inverso — a fila do Gratuito é
-- inteira, o que muda é quem toca o botão.
--
-- A coluna existe desde a 0045 justamente para isto. Ela não se autofiscaliza;
-- esta verificação é a fiscalização.
v_achou := null;
select string_agg(pl.codigo || ' → ' || m, ', ') into v_achou
  from public.planos pl
  cross join unnest(v_mortas) as m
 where exists (select 1 from unnest(pl.recursos) r where position(lower(m) in lower(r)) > 0);
if v_achou is not null then
  raise exception 'FALHOU 15: recursos descreve software que não existe: %', v_achou;
end if;
raise notice 'ok 15 · nenhuma das oito palavras mortas está sendo vendida';

-- 16 · Quatro delas estão em `por_vir` — sumir não é o mesmo que resolver.
--
-- Se a 0064 tivesse só apagado as linhas, a página ficaria honesta e muda, e a
-- pergunta "vocês vão ter NFS-e?" continuaria sem resposta em lugar nenhum.
select count(*)::integer into v_n
  from (select unnest(por_vir) as p from public.planos) t
 where position('NFS-e' in t.p) > 0
    or position('repasse' in t.p) > 0
    or position('salas' in t.p) > 0
    or position('fila cruzada' in t.p) > 0;
if v_n < 4 then
  raise exception 'FALHOU 16: só % das quatro linhas prometidas aparecem em por_vir — apagar não é responder', v_n;
end if;
raise notice 'ok 16 · o que saiu de recursos foi para por_vir, sob rótulo';

-- 17 · O banco recusa a mesma linha nas duas listas.  ← decide
v_erro := null;
begin
  set local role postgres;
  update public.planos set por_vir = array['tudo do Gratuito'] where codigo = 'solo';
  reset role;
exception when others then
  v_erro := sqlerrm;
  reset role;
end;
if v_erro is null then
  raise exception 'FALHOU 17: o banco aceitou vender e prometer a mesma linha';
end if;
raise notice 'ok 17 · vender e prometer a mesma coisa é recusado pelo banco';

-- 18 · E recusa também quando a interseção é de um item entre muitos.
--
-- É o caso realista: ninguém vai duplicar uma lista inteira. O que acontece é
-- alguém acrescentar uma linha a `por_vir` sem lembrar que ela já está em
-- `recursos` — e é exatamente esse `update` que precisa cair.
v_erro := null;
begin
  set local role postgres;
  update public.planos
     set por_vir = array['coisa nova A', 'modo Receita Saúde', 'coisa nova B']
   where codigo = 'solo';
  reset role;
exception when others then
  v_erro := sqlerrm;
  reset role;
end;
if v_erro is null then
  raise exception 'FALHOU 18: a interseção de um item só passou';
end if;
raise notice 'ok 18 · um item repetido entre muitos também é recusado';

-- 19 · Nenhum plano ficou com `recursos` vazio.
--
-- A 0064 esvazia as duas listas antes de preencher, porque a restrição de
-- disjunção reprovaria o preenchimento parcial. Se um `update` falhar no meio,
-- o plano fica vendido sem uma linha de descrição.
select string_agg(codigo, ', ') into v_txt
  from public.planos where cardinality(recursos) = 0;
if v_txt is not null then
  raise exception 'FALHOU 19: plano(s) sem recurso nenhum: % — o esvaziamento da 0064 não foi refeito', v_txt;
end if;
raise notice 'ok 19 · todo plano diz o que faz';

-- 20 · O Gratuito não tem `por_vir`.
--
-- Ele é o degrau de entrada e ele já entrega. Uma lista de "em breve" no plano
-- de graça é a promessa que a segunda auditoria da landing achou no funil, com
-- outra roupa: quem está avaliando o produto lê "em breve" como "ainda não
-- serve".
select cardinality(por_vir) into v_n from public.planos where codigo = 'gratis';
if v_n <> 0 then
  raise exception 'FALHOU 20: o Gratuito ganhou % promessa(s)', v_n;
end if;
raise notice 'ok 20 · o Gratuito não promete nada, ele entrega';

raise notice '--- parte 5 · o preço por profissional ---';

-- 21 · Só a Clínica.
select string_agg(codigo, ', ') into v_txt
  from public.planos
 where preco_por_profissional_centavos is not null and codigo <> 'clinica';
if v_txt is not null then
  raise exception 'FALHOU 21: plano de preço fixo ganhou acréscimo por profissional: %', v_txt;
end if;
select preco_por_profissional_centavos into v_n from public.planos where codigo = 'clinica';
if v_n is distinct from 3900 then
  raise exception 'FALHOU 21: a Clínica cobra % por profissional (esperado 3900)', v_n;
end if;
raise notice 'ok 21 · só a Clínica tem acréscimo, e ele é R$ 39';

-- 22 · A fatura NÃO usa o número novo.  ← decide
--
-- É a verificação mais estranha do arquivo e é a mais importante da parte. A
-- 0064 põe o número no banco **e deixa a cobrança sem ele de propósito**:
-- mudar a aritmética de fatura sem gateway (B16) e sem cliente é construir
-- cedo, e cobrar errado destrói confiança de um jeito que não se recupera.
--
-- Então o dado existe para a tela ler, e a `abrir_assinatura` continua na
-- fonte única de sempre. No dia em que a cobrança passar a multiplicar, quem
-- fizer isso tem de vir aqui apagar esta verificação — e escrever por quê.
select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname = 'abrir_assinatura';
if v_def is null then
  raise exception 'FALHOU 22: abrir_assinatura sumiu';
end if;
if position('preco_centavos' in v_def) = 0 then
  raise exception 'FALHOU 22: abrir_assinatura não lê mais preco_centavos';
end if;
if position('preco_por_profissional' in v_def) > 0 then
  raise exception 'FALHOU 22: a fatura passou a multiplicar por profissional sem o gateway existir (B16)';
end if;
raise notice 'ok 22 · a fatura continua no preço de tabela, e é decisão';

-- 23 · A conta da landing bate com o banco.
select preco_centavos + 4 * preco_por_profissional_centavos into v_n
  from public.planos where codigo = 'clinica';
if v_n <> 40500 then
  raise exception 'FALHOU 23: cinco profissionais dão % centavos, e a landing diz R$ 405,00', v_n;
end if;
raise notice 'ok 23 · cinco profissionais = R$ 405,00, no banco e na página';

raise notice '--- parte 6 · nada disto virou cerca ---';

-- 24 · Só `faixa_da_conta` lê a faixa.  ← decide
--
-- A faixa é medida e dita, nunca aplicada (0060). A garantia disso não é a
-- ausência de código: é a presença desta varredura. Qualquer função nova que
-- consulte `limite_sessoes_mes` está, por construção, prestes a decidir alguma
-- coisa com base nele — e a única decisão honesta que ele autoriza é uma frase
-- na tela.
--
-- `position` e não `like`: `limite_sessoes_mes` tem três `_`, e em `LIKE` cada
-- um casaria com qualquer caractere. Foi assim que a suíte 0060 acusou código
-- correto três dias atrás.
select string_agg(p.proname, ', ') into v_txt
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public'
   and p.prokind = 'f'
   and p.proname <> 'faixa_da_conta'
   and position('limite_sessoes_mes' in pg_get_functiondef(p.oid)) > 0;
if v_txt is not null then
  raise exception 'FALHOU 24: % lê(em) a faixa — a faixa não decide nada além de uma frase', v_txt;
end if;
raise notice 'ok 24 · só faixa_da_conta lê a faixa, e ela só devolve números';

-- 25 · "sem faixa de sessões" no cartão exige `faixa_e_fair_use` no banco.
--
-- **Esta verificação existe porque uma leitura externa achou a contradição
-- aparente**, e a contradição é real se as duas metades se separarem: o
-- Consultório Completo e a Clínica dizem "sem faixa de sessões" em `recursos` e
-- têm `limite_sessoes_mes = 200` no banco.
--
-- As duas coisas convivem por causa de uma terceira: `faixa_e_fair_use`. Com
-- ela ligada, o 200 é número **meu** — serve para eu enxergar a clínica
-- disfarçada de autônoma — e o `lib/faixa.ts` cala: `nivelDaFaixa` devolve
-- "nenhum", `fraseDaFaixa` devolve string vazia, `fraseDoRestante` diz "seu
-- plano não tem faixa de sessões". A página e a tela dizem a mesma coisa.
--
-- O que **não** pode acontecer é alguém desligar o fair-use e deixar a frase.
-- Aí o cartão venderia "sem faixa" e a tela dela começaria a avisar que faltam
-- 12 sessões — a página mentindo numa das duas pontas.
select string_agg(pl.codigo, ', ') into v_txt
  from public.planos pl
 where exists (select 1 from unnest(pl.recursos) r where position('sem faixa' in r) > 0)
   and not pl.faixa_e_fair_use;
if v_txt is not null then
  raise exception 'FALHOU 25: % diz(em) "sem faixa" no cartão sem faixa_e_fair_use — a tela vai contar sessões que a página promete não contar', v_txt;
end if;

-- E o contrário: fair-use ligado sem a frase seria o número virando faixa
-- vendida por omissão.
select string_agg(pl.codigo, ', ') into v_txt
  from public.planos pl
 where pl.faixa_e_fair_use
   and not exists (select 1 from unnest(pl.recursos) r where position('sem faixa' in r) > 0);
if v_txt is not null then
  raise exception 'FALHOU 25: % tem fair-use e não diz "sem faixa" — o número vira faixa vendida por omissão', v_txt;
end if;
raise notice 'ok 25 · "sem faixa" no cartão e fair-use no banco andam juntos, nos dois sentidos';

-- 26 · O número próprio só é prometido no plano em que ele vai morar.
--
-- Decisão do Leandro em 02/09, e a migração 0065 a aplicou. O `claude/25`
-- desenhava o número próprio como add-on de R$ 19 comprável no Consultório; ele
-- decidiu que é o Consultório Completo inteiro.
--
-- **Uma promessa no cartão errado é pior que promessa nenhuma:** a pessoa lê no
-- Consultório que o número próprio está vindo, assina o Consultório, e descobre
-- depois que ele nunca vem naquele plano. `por_vir` foi criada na 0064
-- justamente para não virar um segundo lugar onde se promete sem conferir — e
-- esta verificação é o que impede isso de acontecer com a primeira linha que
-- ela recebeu.
select string_agg(pl.codigo, ', ') into v_txt
  from public.planos pl
 where exists (select 1 from unnest(pl.por_vir) v where position('número próprio' in lower(v)) > 0)
   and pl.codigo not in ('pro', 'clinica');
if v_txt is not null then
  raise exception 'FALHOU 26: % promete(m) número próprio, e ele mora no Completo e na Clínica', v_txt;
end if;

select count(*)::integer into v_n
  from public.planos pl
 where pl.codigo in ('pro', 'clinica')
   and exists (select 1 from unnest(pl.por_vir) v where position('número próprio' in lower(v)) > 0);
if v_n <> 2 then
  raise exception 'FALHOU 26: só % dos dois planos que recebem o número próprio o anunciam', v_n;
end if;
raise notice 'ok 26 · o número próprio é prometido só onde vai morar';

-- ============================================================ epílogo
--
-- As quarenta sessões da verificação 9 não podem ficar. Elas são exatamente o
-- volume que o medidor da 11 procura, e uma conta de suíte esquecida na lista
-- do operador é lixo dentro da única lista que essa decisão produziu — e uma
-- lista com lixo dentro é uma lista que ninguém abre, que é o argumento da
-- própria 11. A 11 marca a conta como teste e isso a esconde do medidor, mas
-- esconder não é apagar: a conta continuaria contando sessões para sempre.
--
-- A ordem é a mesma do preâmbulo, e pelo mesmo motivo de chave estrangeira.
set local role postgres;
delete from public.sessoes    where conta_id in (v_a_conta, v_b_conta);
delete from public.pacientes  where conta_id in (v_a_conta, v_b_conta);
delete from auth.users where id in (v_a_auth, v_b_auth);
delete from public.profissionais where conta_id in (v_a_conta, v_b_conta);
delete from public.usuarios      where conta_id in (v_a_conta, v_b_conta);
delete from public.contas where nome in ('Planos Teste', 'Planos Vizinha');
reset role;

raise notice '';
raise notice '=== 0064 · 26 verificações, e nenhuma delas construiu recurso ===';

end $do$;
