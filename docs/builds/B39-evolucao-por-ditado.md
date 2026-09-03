# B39 · Evolução por ditado — e o registro que não se perde

**3 dias (era 2; +1 pelo S1 da auditoria) · migração: a definir · quarta da fila**

---

## Por que esta build cresceu

O escopo original era ditar a evolução em vez de digitar, **no dispositivo dela,
sobre a fala dela**, depois da sessão. A auditoria de UX achou, no mesmo
componente, um **S1**: a evolução pode ser gravada no prontuário do paciente
errado. Como o conserto e o ditado moram no mesmo lugar, entram juntos — e o S1
vem primeiro.

---

## O S1 · "Escrevi a evolução da Helena e ela foi parar no prontuário do João"

```
components/app/Semana.tsx:207-215
  {sessaoAberta && (
    <div className="mt-4">
      <PainelSessao sessao={sessaoAberta} ... />   // ← sem `key`
    </div>
  )}

components/app/Registro.tsx:138  <input type="hidden" name="sessao_id" value={sessaoId} />
components/app/Registro.tsx:147  <textarea name="texto" defaultValue={texto ?? ""} ... />
```

`<PainelSessao>` é renderizado **sem `key`**, no mesmo lugar da árvore. Tocar em
outra sessão troca as props sem desmontar o componente. O `hidden` é controlado
por `value` e **atualiza**; a `<textarea>` é não-controlada por `defaultValue` e
**não atualiza** — o texto digitado permanece no DOM.

**Reproduzir** (fim de dia, duas sessões já `realizada`, que é quando a
`<Evolucao>` aparece — `PainelSessao.tsx:434-446`):
1. abrir a sessão A na lista do dia;
2. digitar a evolução, **sem salvar**;
3. tocar na sessão B na mesma lista (sem fechar o painel);
4. tocar em Guardar.

O texto de A é gravado na sessão de B. Guarda de cinco anos, e
`evolucao_nao_se_reescreve` impede desfazer.

**Agravante do mesmo componente:** não existe rascunho em lugar nenhum do
repositório — busca por `localStorage`, `sessionStorage`, `indexedDB`,
`beforeunload`, `autosave`: **zero ocorrências**. Sair da tela perde o texto sem
aviso, e ela escreve isso de pé, entre sessões, num aparelho que descarta PWA em
segundo plano.

---

## Entrega

**1 · `key={sessaoAberta.id}` no `<PainelSessao>`.** Uma palavra. Faz o React
desmontar e remontar, e todo estado interno — inclusive o DOM da textarea — nasce
limpo.

**2 · Rascunho local.** Salvar o conteúdo da textarea em `localStorage` a cada
pausa de digitação, com chave por `sessao_id`, e reidratar no mount. Apagar ao
gravar com sucesso. **Só o rascunho da evolução em curso** — não é cache de
prontuário.

**3 · O ditado.** Ditar a evolução no dispositivo dela, sobre a fala dela, depois
da sessão. Áudio **apagado após a transcrição** (decisão de 02/09). Consentimento
explícito e revogável.

**4 · Enquanto o painel está aberto, dar sinal de vida.** `scrollIntoView` na
abertura e estado visual de "selecionada" na linha tocada — hoje o painel abre
depois da lista dos sete dias inteira, sem marca nenhuma (é o primeiro item da
B47, e cabe aqui porque é o mesmo componente).

---

## Pronto quando

- [ ] trocar de sessão com texto não salvo **não** carrega o texto para a
      segunda;
- [ ] fechar o app no meio de uma evolução e reabrir devolve o texto;
- [ ] gravar apaga o rascunho;
- [ ] o áudio não existe em lugar nenhum depois da transcrição, verificado no
      storage;
- [ ] tocar numa sessão no celular leva o painel ao campo de visão.

---

## Não entra

- **Gravar paciente, transcrever sessão, IA interpretando.** É a fronteira 1, e
  cinco dos oito concorrentes atravessam. O Manual de nov/2025 pede "síntese
  acima de volume" — a norma e a fronteira apontam para o mesmo lado.
- **Cachear a agenda ou o prontuário no aparelho.** O rascunho é o texto em
  curso, e só.
- **Tornar a textarea controlada.** Resolve a troca e piora o resto: re-render a
  cada tecla numa tela que já faz quinze consultas. A `key` resolve o mesmo com
  custo zero.

---

## Arquivos que esta build toca

```
components/app/Semana.tsx        ← a `key`
components/app/Registro.tsx      ← o rascunho e o ditado
components/app/PainelSessao.tsx
app/(app)/pacientes/acoes.ts     ← escreverEvolucao
```
