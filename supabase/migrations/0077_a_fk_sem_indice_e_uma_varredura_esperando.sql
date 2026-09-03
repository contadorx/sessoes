-- 0077 · As vinte chaves estrangeiras que ficaram sem índice.
--
-- A lei 2 do `CLAUDE.md` diz três coisas, e a terceira é *"FK sempre
-- indexada"*. A 0045e cumpriu a lei em três chaves da OP1 e escreveu por quê:
-- uma FK sem índice do lado que referencia obriga o Postgres a **varrer a
-- tabela inteira a cada delete ou update da chave do lado referenciado**.
--
-- Depois da 0045e a lei parou de ser conferida, e vinte chaves nasceram sem
-- índice em quinze builds diferentes. Não foram encontradas lendo: a consulta
-- que as achou é a varredura do catálogo — `pg_constraint` com `contype = 'f'`
-- cruzado com `pg_index`, pedindo que as colunas iniciais de algum índice
-- sejam exatamente as da chave. Essa consulta agora mora em dois lugares que
-- rodam sem ninguém pedir: a suíte 0077 e a prova do restore.
--
-- **Por que isto importa aqui e não é só "consulta lenta".** Três dos vinte
-- casos são o caminho de apagar gente:
--
--   · `arquivar_paciente` e o expurgo da B13 apagam paciente. Sem índice em
--     `mensagens_recebidas.paciente_id`, `ofertas_fixas.paciente_id`,
--     `vagas_fixas.novo_paciente` e `vagas_fixas.paciente_anterior`, cada
--     apagamento varre quatro tabelas inteiras.
--   · `eliminar_conta` (0062) apaga a conta toda. `avisos_assinatura.conta_id`,
--     `ofertas_fixas.conta_id` e `pacote_consumos.conta_id` são varredura
--     completa no meio da operação que a LGPD dá prazo para concluir.
--   · `cancelar_sessao` e a remarcação mexem em `sessoes`. `sessoes.reposta_por`
--     e `remarcacoes.nova_sessao_id` apontam para sessão, e a B21 apaga sessão.
--
-- Hoje nada disso dói, porque as tabelas são pequenas. É exatamente o que a
-- 0045e escreveu: *"também não vai doer com trezentas, e vai começar a doer
-- sozinho num dia qualquer, num lugar que ninguém está olhando"*.
--
-- Índice parcial onde a coluna é anulável — `col = X` implica `col is not
-- null`, então o planejador usa o índice parcial para a checagem da FK, e é o
-- padrão que a 0045e já tinha usado em `faturas_da_assinatura`.

-- ------------------------------------------------------ colunas obrigatórias

create index if not exists aceites_do_contrato
  on public.aceites (contrato_id);

create index if not exists anamneses_do_profissional
  on public.anamneses (profissional_id);

create index if not exists avaliacoes_do_plano
  on public.avaliacoes (plano);

create index if not exists avisos_da_conta
  on public.avisos_assinatura (conta_id);

create index if not exists ofertas_fixas_da_conta
  on public.ofertas_fixas (conta_id);

create index if not exists ofertas_fixas_do_paciente
  on public.ofertas_fixas (paciente_id);

create index if not exists consumos_da_conta
  on public.pacote_consumos (conta_id);

-- --------------------------------------------------------- colunas anuláveis

create index if not exists cobrancas_da_proposta
  on public.cobrancas (proposta_id)
  where proposta_id is not null;

create index if not exists eventos_da_oferta
  on public.eventos_fila (oferta_id)
  where oferta_id is not null;

create index if not exists eventos_da_vaga_fixa
  on public.eventos_fila (vaga_fixa_id)
  where vaga_fixa_id is not null;

create index if not exists eventos_da_cobranca
  on public.eventos_pagamento (cobranca_id)
  where cobranca_id is not null;

create index if not exists recebidas_da_oferta
  on public.mensagens_recebidas (oferta_id)
  where oferta_id is not null;

create index if not exists recebidas_do_paciente
  on public.mensagens_recebidas (paciente_id)
  where paciente_id is not null;

create index if not exists pacotes_do_enquadre
  on public.pacotes (enquadre_id)
  where enquadre_id is not null;

create index if not exists propostas_do_enquadre
  on public.propostas_de_cobranca (enquadre_id)
  where enquadre_id is not null;

create index if not exists remarcacoes_da_nova_sessao
  on public.remarcacoes (nova_sessao_id)
  where nova_sessao_id is not null;

create index if not exists sessoes_repostas_por
  on public.sessoes (reposta_por)
  where reposta_por is not null;

create index if not exists vagas_fixas_do_enquadre
  on public.vagas_fixas (enquadre_id)
  where enquadre_id is not null;

create index if not exists vagas_fixas_do_novo_paciente
  on public.vagas_fixas (novo_paciente)
  where novo_paciente is not null;

create index if not exists vagas_fixas_do_paciente_anterior
  on public.vagas_fixas (paciente_anterior)
  where paciente_anterior is not null;
