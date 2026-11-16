document.getElementById('login-form').addEventListener('submit', async function(e) {
    e.preventDefault(); // Stop the form from submitting normally

    const username = document.getElementById('username').value;
    const password = document.getElementById('password').value;
    const errorMessage = document.getElementById('error-message');

    try {
        const response = await fetch('/api/auth/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ username, password }),
        });

        const data = await response.json();

        if (response.ok) {
            // Login successful! Redirect to the main dashboard.
            window.location.href = '/dashboard';
        } else {
            // Show error message
            errorMessage.textContent = data.message || 'Login failed.';
        }
    } catch (error) {
        errorMessage.textContent = 'An error occurred. Please try again.';
    }
});