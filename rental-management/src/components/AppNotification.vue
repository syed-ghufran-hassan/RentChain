<!-- AppNotification.vue -->
<template>
  <div v-if="notifications.length">
    <h3>Notifications</h3>
    <ul>
      <li v-for="(notification, index) in notifications" :key="index">
        {{ notification.message }} - {{ notification.date }}
      </li>
    </ul>
  </div>
</template>

<script>
export default {
  data() {
    return {
      notifications: []
    };
  },
  methods: {
    addNotification(message) {
      this.notifications.push({
        message,
        date: new Date().toLocaleString()
      });
    },
    listenForEvents() {
  // Listen for rent payment due events
  this.contract.events.RentPaymentDue({}, (error) => {
    if (!error) {
      this.addNotification('Rent payment is due soon!');
    }
  });

  // Listen for agreement expiration events
  this.contract.events.AgreementExpiring({}, (error) => {
    if (!error) {
      this.addNotification('Your rental agreement is expiring soon.');
    }
  });

    }
  },
  mounted() {
    if (this.$parent.contract) {
      this.contract = this.$parent.contract;
      this.listenForEvents();
    } else {
      alert('Please connect your wallet.');
    }
  }
};
</script>
