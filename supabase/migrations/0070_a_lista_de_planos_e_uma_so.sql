-- 0070 · A lista de recursos dos planos é uma só.
--
-- "A promessa que o software não cumpre" é um antipadrão nomeado deste projeto
-- e já aconteceu quatro vezes. A 0064 fechou a porta pela qual ele entrava:
-- criou `planos.por_vir` e a restrição `planos_promessa_nao_e_recurso`, para
-- que o que não existe não pudesse ser listado como recurso.
--
-- **E ele voltou assim mesmo**, no cartão de R$ 129 da landing, como
-- "permissões por pessoa: quem vê o quê, **com aprovação em etapas**" — sem
-- implementação em `app/`, `lib/` ou `supabase/`. Passou porque a trava mora na
-- coluna do banco e **a landing renderiza a constante do TypeScript**
-- (`lib/planos.ts`), que ninguém comparava com a coluna.
--
-- Comparadas agora, as duas divergiam em seis linhas, e não só na que trouxe a
-- promessa de volta:
--
--   gratis  · "o registro de cada horário"          ≠ "o registro do que
--             aconteceu com cada horário"
--           · "lembrete ... , automáticos"           ≠ "... saem sozinhos"
--   solo    · "... pelo número do Sessões"           ≠ "... na hora em que a
--             vaga abre"
--           · "faixa de 60 sessões por mês"          ≠ "60 sessões por mês"
--           · "modo Receita Saúde" + "pasta do contador" (duas linhas) ≠ uma
--           · faltava "Receita por hora disponível e o que aconteceu com cada
--             horário"
--
-- Nenhuma delas era mentira; juntas eram duas descrições do mesmo produto,
-- e a que ninguém via era a que estava protegida.
--
-- **O que esta migração faz é escolher uma.** A do TypeScript, porque é a que a
-- pessoa lê. E o texto abaixo foi **gerado a partir de `lib/planos.ts`**, não
-- transcrito — transcrever à mão é como as seis nasceram.
--
-- A partir daqui as duas ficam presas uma à outra por duas verificações:
-- `lib/planos.test.ts` compara a constante com **este arquivo**, e a suíte
-- `supabase/tests/0070_*.sql` compara **o banco** com a mesma lista. Uma metade
-- que mude sozinha reprova — é o mesmo espelho que a 0066 pôs nos templates,
-- pela mesma razão.
--
-- "Aprovação em etapas" não foi apagada: virou linha de `por_vir`, sob o rótulo
-- "Ainda não existe, e não está no preço". Apagar deixaria a página honesta e
-- muda sobre uma intenção que é real.

update public.planos set
  recursos = array[
    'Agenda, prontuário e o registro do que aconteceu com cada horário',
    'Pacientes sem limite',
    'Sessões sem limite',
    'Fila e página da vaga, completas',
    'Lembrete de véspera e aviso de desmarque saem sozinhos',
    'Política de cancelamento congelada no contrato',
    'Cobrança, recibo e informe',
    'A fila e a cobrança saem do seu WhatsApp, com um toque seu'
  ],
  por_vir = '{}'::text[]
where codigo = 'gratis';

update public.planos set
  recursos = array[
    'Tudo do Gratuito',
    'A fila e a cobrança saem sozinhas, na hora em que a vaga abre',
    '60 sessões por mês',
    'Modo Receita Saúde e pasta do contador',
    'Régua de atraso impessoal',
    'Receita por hora disponível e o que aconteceu com cada horário'
  ],
  por_vir = '{}'::text[]
where codigo = 'solo';

update public.planos set
  recursos = array[
    'Tudo do Consultório',
    'Sem faixa de sessões',
    'Permissões por pessoa: quem vê o quê'
  ],
  por_vir = array[
    'NFS-e para quem atende como PJ',
    'Número próprio: as mensagens chegam do número que suas pacientes já conhecem',
    'Página do paciente: confirmar, pagar e receber documento',
    'Reajuste assistido e modo férias',
    'Aprovação em etapas para quem tem permissão limitada'
  ]
where codigo = 'pro';

update public.planos set
  recursos = array[
    'Tudo do Consultório Completo',
    'Vários profissionais, com sigilo entre eles por construção',
    'Sem faixa de sessões, por profissional que atende'
  ],
  por_vir = array[
    'Repasse e demonstrativo por profissional',
    'Agenda de salas',
    'Fiscal consolidado da clínica',
    'Fila cruzada entre profissionais',
    'Número próprio da clínica'
  ]
where codigo = 'clinica';

-- A restrição da 0064 continua valendo, e é ela que impede a próxima promessa
-- de nascer como recurso. Esta migração não a toca — só a respeita.
