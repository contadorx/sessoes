-- 0045e · As FKs do negócio ganham índice.
--
-- Os advisors do Supabase acusaram três chaves estrangeiras sem índice de
-- cobertura, todas nascidas na 0045:
--
--     contas.contas_plano_fk               → planos(codigo)
--     assinaturas.assinaturas_plano_codigo → planos(codigo)
--     faturas.faturas_assinatura_id_fkey   → assinaturas(id)
--
-- É a mesma classe de achado da B26, e vale repetir por que ela importa mais
-- do que "consulta lenta". Uma FK sem índice do lado que referencia obriga o
-- Postgres a varrer a tabela inteira **a cada delete ou update da chave do
-- lado referenciado** — e as três apontam para tabelas pequenas cuja chave é
-- justamente a que eu vou mexer: renomear o código de um plano, ou apagar uma
-- assinatura, encostaria em `contas` e `faturas` por varredura completa.
--
-- Hoje isso não custa nada porque há três contas. O problema é que também não
-- vai doer com trezentas, e vai começar a doer sozinho num dia qualquer, num
-- lugar que ninguém está olhando. Índice de FK é barato agora e caro de
-- descobrir depois.
--
-- Os outros dois avisos que os advisors levantaram sobre esta build são
-- **intencionais e ficam como estão**:
--
--   · `rls_enabled_no_policy` em `precos_canal` e `custos_fixos` — RLS ligada
--     e nenhuma política é exatamente o desenho: zero linha para todo mundo
--     que não seja `service_role`. Mesmo padrão de `calendarios_segredo`.
--
--   · `authenticated_security_definer_function_executable` em `e_operador`,
--     `painel_do_negocio` e `contas_do_painel` — as três precisam ser
--     chamáveis por `authenticated` porque eu chego pela minha própria sessão,
--     autenticado como qualquer pessoa. Quem barra é o `e_operador()` conferido
--     por dentro de cada uma, e a verificação 3 da suíte 0045 prova que barra.

create index if not exists contas_do_plano
  on public.contas (plano);

create index if not exists assinaturas_do_plano
  on public.assinaturas (plano_codigo);

create index if not exists faturas_da_assinatura
  on public.faturas (assinatura_id)
  where assinatura_id is not null;
