-- 0075 · `revoke ... from anon` não revoga nada
--
-- Achado conferindo a 0074, e ele é meu, das duas migrações anteriores.
--
-- A 0072 e a 0073 terminam com linhas assim:
--
--     revoke execute on function public.anotar_objetivo(uuid, text, date) from anon;
--     revoke execute on function public.reajustar_enquadre(...) from anon;
--
-- **Elas não fizeram nada.** No Postgres, `EXECUTE` numa função nova é
-- concedido a `PUBLIC` por padrão, e `anon` é membro de PUBLIC. Revogar de
-- `anon` remove uma concessão direta que nunca existiu; a de PUBLIC continua
-- de pé, e `has_function_privilege('anon', ..., 'execute')` continua devolvendo
-- `true`. A linha fica no arquivo com cara de tranca e não tranca.
--
-- A 0068 acertou por acidente de redação — ela escreve
-- `from public, anon, authenticated`, e é o `public` que resolve. Conferido:
-- `passar_para_a_sua_mao` é a única das recentes fora do alcance do `anon`.
--
-- **O que isso expunha, na prática.** Todas as funções afetadas são
-- `security invoker`: elas rodam com os direitos de quem chama, e a RLS
-- continua respondendo — `anon` não tem `conta_atual()`, então um `insert` em
-- `objetivos` ou um `update` em `enquadres` seria recusado pela policy de
-- qualquer jeito. Não era buraco aberto; era **tranca de mentira**, que é o
-- tipo de coisa que engana a próxima leitura. No dia em que uma dessas virasse
-- `security definer` por qualquer razão, a linha do arquivo diria que estava
-- fechada.
--
-- **O que continua aberto de propósito, e conferi antes de mexer:** as nove
-- funções `security definer` que o `anon` executa são exatamente as páginas por
-- link — `aceitar_contrato`, `confirmar_pelo_link`, `contrato_por_token`,
-- `documento_do_link`, `escolher_remarcacao`, `ficha_do_paciente`,
-- `pagina_do_paciente`, `remarcacao_por_token`, `salvar_ficha`. Quem abre um
-- link não tem conta aqui, e a tranca delas é o token.
--
-- ⚠️ **A frase que estava aqui era "nenhuma sobra", e era falsa.** Sobrava
-- `arquivar_paciente(uuid, text, text)` — a assinatura nova que a 0071 criou, e
-- que nasceu com `EXECUTE` para `PUBLIC` como toda função nova. A lista de
-- `revoke` abaixo é **escrita à mão**, o antipadrão da lei 7, num arquivo cujo
-- assunto era exatamente esse antipadrão. A 0076 revoga a que faltou, e a
-- detecção passou a ser por catálogo na suíte 0074.
--
-- A verificação 7 da suíte 0074 nasceu errada pelo mesmo motivo: ela lia
-- `information_schema.role_routine_grants`, que **não enxerga concessão a
-- `anon`** a partir do papel que roda a migração — e por isso respondia zero
-- tanto para o que estava fechado quanto para o que estava aberto. Quem
-- responde é `has_function_privilege`, e é o que ela usa agora.

revoke execute on function public.anotar_objetivo(uuid, text, date) from public, anon;
revoke execute on function public.concluir_objetivo(uuid) from public, anon;
revoke execute on function public.remarcar_revisao(uuid, date) from public, anon;
revoke execute on function public.objetivos_do_paciente(uuid) from public, anon;

revoke execute on function public.reajustar_enquadre(uuid, numeric, numeric, date, text) from public, anon;
revoke execute on function public.mensalidades_a_rever(date, date) from public, anon;
revoke execute on function public.rever_mensalidade(uuid) from public, anon;

-- E o `authenticated` precisa continuar executando: é ela, logada, quem chama.
grant execute on function public.anotar_objetivo(uuid, text, date) to authenticated;
grant execute on function public.concluir_objetivo(uuid) to authenticated;
grant execute on function public.remarcar_revisao(uuid, date) to authenticated;
grant execute on function public.objetivos_do_paciente(uuid) to authenticated;

grant execute on function public.reajustar_enquadre(uuid, numeric, numeric, date, text) to authenticated;
grant execute on function public.mensalidades_a_rever(date, date) to authenticated;
grant execute on function public.rever_mensalidade(uuid) to authenticated;
