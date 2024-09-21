<template>
  <div>
    <h2>Available Properties</h2>
    <ul>
      <li v-for="property in properties" :key="property.id">
        {{ property.name }} - {{ property.location }} - {{ property.rentPerMonth }} ETH
      </li>
    </ul>
  </div>
</template>

<script>
export default {
  data() {
    return {
      properties: [],
    };
  },
  methods: {
    async getProperties() {
      const contract = this.$root.contract;
      const properties = await contract.methods.viewProperties().call();
      this.properties = properties.map((prop, index) => ({
        id: index,
        name: prop.name,
        location: prop.location,
        rentPerMonth: this.$root.web3.utils.fromWei(prop.rentPerMonth, 'ether')
      }));
    }
  },
  mounted() {
    this.getProperties();
  }
};
</script>
