from intl import Intl, define_message


GREETING = define_message(
    id="python.greeting",
    default_message="Hello, {name}!",
    description="Greeting from Python",
)


def render_messages(intl: Intl, name: str, total: float) -> tuple[str, str, str, str]:
    greeting = intl.format_message(
        "python.runtime.greeting",
        default_message="Welcome, {name}!",
        description="Greeting shown after sign-in",
        values={"name": name},
    )
    ready = intl.format_message(
        id="python.runtime.ready",
        default_message="Ready",
    )
    missing = intl.format_message("python.runtime.missing")
    total_label = intl.format_message(
        default_message="Your total is {total, number, ::currency/USD}.",
        description="Checkout total",
        values={"total": total},
    )
    return greeting, ready, missing, total_label
