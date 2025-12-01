<script lang="ts">
  interface Props {
    isHeating?: boolean;
  }

  let { isHeating = false }: Props = $props();
</script>

<span
  class="badge text-primary-content"
  class:bg-cooling={!isHeating}
  class:bg-heating={isHeating}
  >{isHeating ? 'Heating' : 'Cooling'}
</span>
