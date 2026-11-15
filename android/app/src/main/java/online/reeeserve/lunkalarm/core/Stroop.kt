package online.reeeserve.lunkalarm.core

import kotlin.random.Random

enum class StroopColor(val label: String) { RED("Red"), BLUE("Blue"), GREEN("Green"), YELLOW("Yellow") }

data class StroopRound(val word: StroopColor, val ink: StroopColor, val buttonColors: List<StroopColor>,
    val choiceOrder: List<StroopColor> = StroopColor.entries) {
    fun validate() {
        require(word != ink && buttonColors.size == StroopColor.entries.size && buttonColors.toSet().size == StroopColor.entries.size)
        require(choiceOrder.size == StroopColor.entries.size && choiceOrder.toSet() == StroopColor.entries.toSet())
        require(choiceOrder.zip(buttonColors).all { (label, background) -> label != background })
    }
    companion object {
        private fun orders(colors: List<StroopColor>): List<List<StroopColor>> =
            if (colors.isEmpty()) listOf(emptyList()) else colors.flatMap { color -> orders(colors - color).map { listOf(color) + it } }
        fun create(previous: StroopRound? = null, random: Random = Random.Default): StroopRound {
            val colors = StroopColor.entries
            val ink = colors.filter { it != previous?.ink }.random(random)
            val word = colors.filter { it != ink }.random(random)
            val choices = orders(colors).filter { order -> previous == null || (
                order.zip(previous.choiceOrder).all { (a, b) -> a != b } &&
                order.indexOf(ink) != previous.choiceOrder.indexOf(previous.ink)
            ) }.random(random)
            val offset = random.nextInt(1, colors.size)
            return StroopRound(word, ink, choices.indices.map { choices[(it + offset) % choices.size] }, choices)
        }
    }
}
