<script lang="ts">
  export let isHeating: boolean = false;
</script>

<span class="badge" class:bg-cooling={!isHeating} class:bgheating={isHeating}
  >{isHeating ? 'Heating' : 'Cooling'}</span
>
