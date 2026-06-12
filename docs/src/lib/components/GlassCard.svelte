<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    title,
    accent,
    icon,
    children
  }: { title: string; accent: string; icon: Snippet; children: Snippet } = $props();
</script>

<div class="card glass">
  <h3>
    <span class="icon" style:color={accent} aria-hidden="true">{@render icon()}</span>
    {title}
  </h3>
  <p>{@render children()}</p>
</div>

<style>
  .card {
    border-radius: var(--radius);
    padding: 26px 28px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    transition: transform var(--dur-3) var(--ease-out-quart);
  }

  @media (hover: hover) {
    .card:hover {
      transform: translateY(-4px);
    }
  }

  h3 {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 19px;
    font-weight: 600;
    letter-spacing: -0.01em;
    color: var(--ink);
  }

  .icon {
    display: inline-grid;
    place-items: center;
  }

  .icon :global(svg) {
    display: block;
  }

  p {
    font-size: 15px;
    font-weight: 300;
    line-height: 1.55;
    color: var(--ink2);
    max-width: 52ch;
  }
</style>
